#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include <cstring>

#include "flutter/generated_plugin_registrant.h"

// Same window sizes as the Windows runner, in logical pixels.
constexpr int kDefaultWidth = 1280;
constexpr int kDefaultHeight = 820;
constexpr int kMinWidth = 480;
constexpr int kMinHeight = 560;

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  FlMethodChannel* desktop_channel;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

static void first_frame_cb(MyApplication* self, FlView* view) {
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

// The "nur/desktop" channel works like the one in the Windows runner: the
// clipboard image as PNG bytes (null when there is none) and the paths of files
// copied in the file manager.
static void clipboard_image_cb(GtkClipboard* clipboard, GdkPixbuf* pixbuf,
                               gpointer user_data) {
  g_autoptr(FlMethodCall) method_call = FL_METHOD_CALL(user_data);
  g_autoptr(FlValue) result = nullptr;
  gchar* png = nullptr;
  gsize size = 0;
  if (pixbuf != nullptr &&
      gdk_pixbuf_save_to_bufferv(pixbuf, &png, &size, "png", nullptr, nullptr,
                                 nullptr)) {
    result =
        fl_value_new_uint8_list(reinterpret_cast<const uint8_t*>(png), size);
    g_free(png);
  } else {
    result = fl_value_new_null();
  }
  fl_method_call_respond_success(method_call, result, nullptr);
}

static void clipboard_uris_cb(GtkClipboard* clipboard, gchar** uris,
                              gpointer user_data) {
  g_autoptr(FlMethodCall) method_call = FL_METHOD_CALL(user_data);
  g_autoptr(FlValue) paths = fl_value_new_list();
  for (gchar** uri = uris; uri != nullptr && *uri != nullptr; uri++) {
    g_autofree gchar* path = g_filename_from_uri(*uri, nullptr, nullptr);
    if (path != nullptr) {
      fl_value_append_take(paths, fl_value_new_string(path));
    }
  }
  fl_method_call_respond_success(method_call, paths, nullptr);
}

static void desktop_method_cb(FlMethodChannel* channel,
                              FlMethodCall* method_call, gpointer user_data) {
  const gchar* method = fl_method_call_get_name(method_call);
  GtkClipboard* clipboard = gtk_clipboard_get(GDK_SELECTION_CLIPBOARD);
  if (strcmp(method, "clipboardImage") == 0) {
    gtk_clipboard_request_image(clipboard, clipboard_image_cb,
                                g_object_ref(method_call));
  } else if (strcmp(method, "clipboardFiles") == 0) {
    gtk_clipboard_request_uris(clipboard, clipboard_uris_cb,
                               g_object_ref(method_call));
  } else {
    fl_method_call_respond_not_implemented(method_call, nullptr);
  }
}

static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

  // A header bar on GNOME and on Wayland; other X11 window managers (tiling
  // ones, for example) get a normal title bar.
  gboolean use_header_bar = TRUE;
#ifdef GDK_WINDOWING_X11
  GdkScreen* screen = gtk_window_get_screen(window);
  if (GDK_IS_X11_SCREEN(screen)) {
    const gchar* wm_name = gdk_x11_screen_get_window_manager_name(screen);
    if (g_strcmp0(wm_name, "GNOME Shell") != 0) {
      use_header_bar = FALSE;
    }
  }
#endif
  if (use_header_bar) {
    GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_title(header_bar, "Nur");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  }
  gtk_window_set_title(window, "Nur");

  // Shrunk to fit small screens.
  int width = kDefaultWidth;
  int height = kDefaultHeight;
  GdkDisplay* display = gtk_widget_get_display(GTK_WIDGET(window));
  GdkMonitor* monitor = gdk_display_get_primary_monitor(display);
  if (monitor == nullptr && gdk_display_get_n_monitors(display) > 0) {
    monitor = gdk_display_get_monitor(display, 0);
  }
  if (monitor != nullptr) {
    GdkRectangle area;
    gdk_monitor_get_workarea(monitor, &area);
    width = MIN(width, MAX(kMinWidth, area.width - 40));
    height = MIN(height, MAX(kMinHeight, area.height - 40));
  }
  gtk_window_set_default_size(window, width, height);
  GdkGeometry hints = {};
  hints.min_width = kMinWidth;
  hints.min_height = kMinHeight;
  gtk_window_set_geometry_hints(window, nullptr, &hints, GDK_HINT_MIN_SIZE);
  gtk_window_set_position(window, GTK_WIN_POS_CENTER);

  // The icon is installed as data/nur.png next to the binary.
  g_autofree gchar* exe = g_file_read_link("/proc/self/exe", nullptr);
  if (exe != nullptr) {
    g_autofree gchar* dir = g_path_get_dirname(exe);
    g_autofree gchar* icon = g_build_filename(dir, "data", "nur.png", nullptr);
    gtk_window_set_icon_from_file(window, icon, nullptr);
  }

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  GdkRGBA background_color;
  gdk_rgba_parse(&background_color, "#000000");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  // The window shows up with the first Flutter frame, which needs a realized
  // view.
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  self->desktop_channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)), "nur/desktop",
      FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(
      self->desktop_channel, desktop_method_cb, self, nullptr);

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // The first argument is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;

  return TRUE;
}

static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  g_clear_object(&self->desktop_channel);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {}

MyApplication* my_application_new() {
  // The program name is the application id, so a desktop entry named
  // app.nur.nur.desktop matches the window.
  g_set_prgname(APPLICATION_ID);

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_NON_UNIQUE, nullptr));
}
