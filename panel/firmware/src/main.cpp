// IP NAS panel firmware for the Guition JC3248W535 (ESP32-S3, AXS15231B 320x480 QSPI display with I2C touch).
// It talks to ipnas_panel_agent.py on the Raspberry Pi over USB, one JSON object per line (docs/PANEL.md).
#include <Arduino.h>
#include <Wire.h>
#include <Preferences.h>
#include <ArduinoJson.h>
#include <Arduino_GFX_Library.h>
#include <lvgl.h>

#define FW_VERSION "1.1.0"

#define PIN_BL 1
#define BL_CH 0
#define TOUCH_SDA 4
#define TOUCH_SCL 8
#define TOUCH_ADDR 0x3B
#define NATIVE_W 320
#define NATIVE_H 480
#define SCR_W 480
#define SCR_H 320

// The panel ignores partial-window writes and cannot rotate, so LVGL draws into a full 320x480 canvas (turned in
// disp_flush) and every flush sends the whole frame.
static Arduino_DataBus *bus = new Arduino_ESP32QSPI(45, 47, 21, 48, 40, 39);
static Arduino_GFX *panel = new Arduino_AXS15231B(bus, GFX_NOT_DEFINED, 0, false, NATIVE_W, NATIVE_H);
static Arduino_Canvas *gfx = new Arduino_Canvas(NATIVE_W, NATIVE_H, panel, 0, 0, 0);
static uint16_t *fb = nullptr;
static Preferences prefs;
static bool flip = false;  // false: USB port on the left; true: turned 180 deg
static int brightness = 200;

#define C_BG       lv_color_hex(0x0B0D0F)
#define C_CARD     lv_color_hex(0x15181C)
#define C_LINE     lv_color_hex(0x23272C)
#define C_BTN      lv_color_hex(0x1F2328)
#define C_TRACK    lv_color_hex(0x262A30)
#define C_LIME     lv_color_hex(0xCCFF00)
#define C_LIME_BG  lv_color_hex(0x27310B)
#define C_TEXT     lv_color_hex(0xF2F4F5)
#define C_DIM      lv_color_hex(0x8A9199)
#define C_FAINT    lv_color_hex(0x50575E)
#define C_AMBER    lv_color_hex(0xFFB020)
#define C_AMBER_BG lv_color_hex(0x3A2C0E)
#define C_RED      lv_color_hex(0xFF5A5A)
#define C_RED_BG   lv_color_hex(0x361818)

LV_IMG_DECLARE(img_logo_28);
LV_IMG_DECLARE(img_logo_96);

static void disp_flush(lv_disp_drv_t *drv, const lv_area_t *a, lv_color_t *px) {
  for (int y = a->y1; y <= a->y2; y++) {
    for (int x = a->x1; x <= a->x2; x++) {
      uint16_t c = (px++)->full;
      if (!flip) fb[x * NATIVE_W + (NATIVE_W - 1 - y)] = c;          // native (319-y, x)
      else       fb[(NATIVE_H - 1 - x) * NATIVE_W + y] = c;          // native (y, 479-x)
    }
  }
  if (lv_disp_flush_is_last(drv)) gfx->flush();
  lv_disp_flush_ready(drv);
}

static int16_t inj_x = -1, inj_y = -1;  // touch injected over serial (TAP x y) for testing
static uint32_t inj_until = 0;

static bool touch_read_raw(int16_t &x, int16_t &y) {
  static const uint8_t cmd[11] = {0xb5, 0xab, 0xa5, 0x5a, 0x0, 0x0, 0x0, 0x8, 0x0, 0x0, 0x0};
  uint8_t d[8] = {0};
  Wire.beginTransmission(TOUCH_ADDR);
  Wire.write(cmd, sizeof(cmd));
  if (Wire.endTransmission() != 0) return false;
  if (Wire.requestFrom((uint8_t)TOUCH_ADDR, (uint8_t)8) != 8) return false;
  for (int i = 0; i < 8; i++) d[i] = Wire.read();
  if (d[0] != 0 || d[1] == 0) return false;
  x = ((d[2] & 0x0F) << 8) | d[3];
  y = ((d[4] & 0x0F) << 8) | d[5];
  return x < NATIVE_W && y < NATIVE_H;
}

static void touch_read(lv_indev_drv_t *, lv_indev_data_t *data) {
  static lv_coord_t lx = 0, ly = 0;
  int16_t rx, ry;
  if (millis() < inj_until) {
    lx = inj_x; ly = inj_y; data->state = LV_INDEV_STATE_PR;
  } else if (touch_read_raw(rx, ry)) {
    if (!flip) { lx = ry; ly = NATIVE_W - 1 - rx; }
    else       { lx = NATIVE_H - 1 - ry; ly = rx; }
    data->state = LV_INDEV_STATE_PR;
  } else {
    data->state = LV_INDEV_STATE_REL;
  }
  data->point.x = lx; data->point.y = ly;
}

static void set_backlight(int v) { ledcWrite(BL_CH, constrain(v, 0, 255)); }

struct Ctr { char name[48]; char image[52]; char state[16]; char status[44]; float cpu; uint64_t mu, ml; };
#define MAX_CTR 24
static Ctr ctrs[MAX_CTR];
static int n_ctr = 0;
struct Net { char ssid[33]; int sig; char sec[17]; bool cur; };
#define MAX_NET 20
static Net nets[MAX_NET];
static int n_net = 0;

static uint32_t last_rx = 0;
static bool linked = false;
static char pi_host[32] = "", pi_ip[40] = "", pi_model[64] = "", pi_os[64] = "", pi_agent[16] = "";
static char cur_ssid[40] = "";
static int cur_sig = 0;
static int next_id = 1;

static lv_obj_t *scr_wait, *scr_main;
static lv_obj_t *top_wifi, *top_clock;
static lv_obj_t *nav_btn[4], *nav_pill[4], *nav_badge;
static lv_obj_t *page[4];
static int cur_page = 0;
// home
static lv_obj_t *arc_cpu, *arc_ram, *arc_tmp, *lbl_cpu, *lbl_ram, *lbl_tmp, *sub_ram;
static lv_obj_t *disk_bar[3], *disk_lbl[3], *disk_val[3];
static lv_obj_t *lbl_rx, *lbl_tx, *lbl_up;
// apps
static lv_obj_t *apps_list, *apps_count, *apps_empty;
static lv_obj_t *app_row[MAX_CTR];
static int n_rows = 0;
// container detail
static lv_obj_t *dlg = nullptr, *dlg_chip, *dlg_status, *dlg_cpu_bar, *dlg_cpu, *dlg_ram_bar, *dlg_ram;
static lv_obj_t *dlg_start, *dlg_pause, *dlg_restart, *dlg_stop, *dlg_del;
static char dlg_name[48] = "";
// wifi
static lv_obj_t *wifi_cur, *wifi_sub, *wifi_icon, *wifi_list, *wifi_scan_btn, *wifi_scan_lbl, *wifi_hint;
static lv_obj_t *net_row[MAX_NET];
static int n_net_rows = 0;
static uint32_t scan_until = 0, last_scan = 0;
// keyboard screen
static lv_obj_t *kbd_scr = nullptr, *kbd_ta, *kbd_eye;
static char kbd_ssid[33] = "";
// busy overlay
static lv_obj_t *busy = nullptr, *busy_lbl;
// settings
static lv_obj_t *set_info, *set_flip_sw;

// pending command
static int pend_id = 0;
static uint32_t pend_until = 0;
static bool pend_wifi = false;

static void fmt_bytes(char *out, size_t n, uint64_t b) {
  double v = (double)b;
  if (v >= 1e12)      snprintf(out, n, "%.2f TB", v / 1e12);
  else if (v >= 1e9)  snprintf(out, n, "%.1f GB", v / 1e9);
  else if (v >= 1e6)  snprintf(out, n, "%.0f MB", v / 1e6);
  else if (v >= 1e3)  snprintf(out, n, "%.0f KB", v / 1e3);
  else                snprintf(out, n, "%u B", (unsigned)b);
}
static void fmt_pair(char *out, size_t n, uint64_t used, uint64_t total) {  // "41 / 293 GB"
  double u = (double)used, t = (double)total;
  if (t >= 1e12)       snprintf(out, n, "%.2f / %.2f TB", u / 1e12, t / 1e12);
  else if (t >= 100e9) snprintf(out, n, "%.0f / %.0f GB", u / 1e9, t / 1e9);
  else                 snprintf(out, n, "%.1f / %.1f GB", u / 1e9, t / 1e9);
}
static void fmt_rate(char *out, size_t n, uint64_t b) {
  double v = (double)b;
  if (v >= 1e6)      snprintf(out, n, "%.1f MB/s", v / 1e6);
  else if (v >= 1e3) snprintf(out, n, "%.0f KB/s", v / 1e3);
  else               snprintf(out, n, "%u B/s", (unsigned)b);
}
static void fmt_uptime(char *out, size_t n, uint32_t s) {
  uint32_t d = s / 86400, h = (s % 86400) / 3600, m = (s % 3600) / 60;
  if (d) snprintf(out, n, "%ud %uh", (unsigned)d, (unsigned)h);
  else if (h) snprintf(out, n, "%uh %um", (unsigned)h, (unsigned)m);
  else snprintf(out, n, "%um", (unsigned)m);
}
static void copy_str(char *dst, size_t n, const char *src) { strncpy(dst, src ? src : "", n - 1); dst[n - 1] = 0; }

static lv_obj_t *box(lv_obj_t *parent) {  // plain container, no style, no scroll
  lv_obj_t *o = lv_obj_create(parent);
  lv_obj_remove_style_all(o);
  lv_obj_clear_flag(o, LV_OBJ_FLAG_SCROLLABLE);
  return o;
}
static lv_obj_t *card(lv_obj_t *parent, int x, int y, int w, int h) {
  lv_obj_t *o = lv_obj_create(parent);
  lv_obj_set_pos(o, x, y); lv_obj_set_size(o, w, h);
  lv_obj_set_style_bg_color(o, C_CARD, 0); lv_obj_set_style_bg_opa(o, LV_OPA_COVER, 0);
  lv_obj_set_style_radius(o, 16, 0); lv_obj_set_style_border_width(o, 1, 0); lv_obj_set_style_border_color(o, C_LINE, 0);
  lv_obj_set_style_pad_all(o, 12, 0); lv_obj_set_style_shadow_width(o, 0, 0);
  lv_obj_clear_flag(o, LV_OBJ_FLAG_SCROLLABLE);
  return o;
}
static lv_obj_t *label(lv_obj_t *parent, const char *txt, const lv_font_t *f, lv_color_t c) {
  lv_obj_t *l = lv_label_create(parent);
  lv_label_set_text(l, txt); lv_obj_set_style_text_font(l, f, 0); lv_obj_set_style_text_color(l, c, 0);
  return l;
}
static lv_obj_t *caption(lv_obj_t *parent, const char *txt) {  // small dim uppercase card title
  lv_obj_t *l = label(parent, txt, &lv_font_montserrat_12, C_DIM);
  lv_obj_set_style_text_letter_space(l, 1, 0);
  return l;
}
static void style_btn(lv_obj_t *b, lv_color_t bg, lv_color_t fg) {
  lv_obj_set_style_bg_color(b, bg, 0); lv_obj_set_style_bg_opa(b, LV_OPA_COVER, 0);
  lv_obj_set_style_radius(b, 14, 0); lv_obj_set_style_shadow_width(b, 0, 0); lv_obj_set_style_border_width(b, 0, 0);
  lv_obj_set_style_text_color(b, fg, 0);
  lv_obj_set_style_bg_color(b, lv_color_hex(0x1A1D21), LV_STATE_DISABLED);
  lv_obj_set_style_text_color(b, C_FAINT, LV_STATE_DISABLED);
}
static lv_obj_t *button(lv_obj_t *parent, const char *txt, lv_color_t bg, lv_color_t fg, int w, int h, lv_event_cb_t cb, void *ud) {
  lv_obj_t *b = lv_btn_create(parent);
  lv_obj_set_size(b, w, h); style_btn(b, bg, fg);
  lv_obj_t *l = label(b, txt, &lv_font_montserrat_16, fg);
  lv_obj_set_style_text_color(l, C_FAINT, LV_STATE_DISABLED);
  lv_obj_center(l);
  if (cb) lv_obj_add_event_cb(b, cb, LV_EVENT_CLICKED, ud);
  return b;
}
// tall action tile: icon on top, word below
static lv_obj_t *tile_btn(lv_obj_t *parent, const char *icon, const char *txt, lv_color_t bg, lv_color_t fg, lv_event_cb_t cb, void *ud) {
  lv_obj_t *b = lv_btn_create(parent);
  lv_obj_set_height(b, 72); lv_obj_set_flex_grow(b, 1); style_btn(b, bg, fg);
  lv_obj_t *i = label(b, icon, &lv_font_montserrat_24, fg); lv_obj_align(i, LV_ALIGN_TOP_MID, 0, 6);
  lv_obj_t *t = label(b, txt, &lv_font_montserrat_14, fg); lv_obj_align(t, LV_ALIGN_BOTTOM_MID, 0, -4);
  if (cb) lv_obj_add_event_cb(b, cb, LV_EVENT_CLICKED, ud);
  return b;
}
static lv_obj_t *chip(lv_obj_t *parent) {
  lv_obj_t *c = box(parent);
  lv_obj_set_size(c, LV_SIZE_CONTENT, LV_SIZE_CONTENT);
  lv_obj_set_style_radius(c, 11, 0); lv_obj_set_style_bg_opa(c, LV_OPA_COVER, 0);
  lv_obj_set_style_pad_hor(c, 9, 0); lv_obj_set_style_pad_ver(c, 3, 0);
  label(c, "", &lv_font_montserrat_12, C_TEXT);
  return c;
}
static void set_chip(lv_obj_t *c, const char *txt, lv_color_t fg, lv_color_t bg) {
  lv_obj_t *l = lv_obj_get_child(c, 0);
  lv_label_set_text(l, txt); lv_obj_set_style_text_color(l, fg, 0); lv_obj_set_style_bg_color(c, bg, 0);
}
static void set_state_chip(lv_obj_t *c, const char *state) {
  if (!strcmp(state, "running"))         set_chip(c, "Running", C_LIME, C_LIME_BG);
  else if (!strcmp(state, "paused"))     set_chip(c, "Paused", C_AMBER, C_AMBER_BG);
  else if (!strcmp(state, "restarting")) set_chip(c, "Restarting", C_AMBER, C_AMBER_BG);
  else if (!strcmp(state, "created"))    set_chip(c, "Created", C_DIM, C_BTN);
  else if (!strcmp(state, "dead"))       set_chip(c, "Dead", C_RED, C_RED_BG);
  else                                   set_chip(c, "Stopped", C_DIM, C_BTN);
}
static lv_obj_t *arc_gauge(lv_obj_t *parent, int size, lv_obj_t **val) {
  lv_obj_t *a = lv_arc_create(parent);
  lv_obj_set_size(a, size, size);
  lv_arc_set_rotation(a, 135); lv_arc_set_bg_angles(a, 0, 270); lv_arc_set_range(a, 0, 100); lv_arc_set_value(a, 0);
  lv_obj_remove_style(a, NULL, LV_PART_KNOB); lv_obj_clear_flag(a, LV_OBJ_FLAG_CLICKABLE);
  lv_obj_set_style_arc_width(a, 8, LV_PART_MAIN); lv_obj_set_style_arc_color(a, C_TRACK, LV_PART_MAIN);
  lv_obj_set_style_arc_width(a, 8, LV_PART_INDICATOR); lv_obj_set_style_arc_color(a, C_LIME, LV_PART_INDICATOR);
  lv_obj_set_style_pad_all(a, 0, 0);
  *val = label(a, "--", &lv_font_montserrat_20, C_TEXT);
  lv_obj_align(*val, LV_ALIGN_CENTER, 0, -2);
  return a;
}
static lv_obj_t *hbar(lv_obj_t *parent, int x, int y, int w, int h) {
  lv_obj_t *b = lv_bar_create(parent);
  lv_obj_set_pos(b, x, y); lv_obj_set_size(b, w, h); lv_bar_set_range(b, 0, 1000);
  lv_obj_set_style_bg_color(b, C_TRACK, LV_PART_MAIN); lv_obj_set_style_bg_opa(b, LV_OPA_COVER, LV_PART_MAIN);
  lv_obj_set_style_bg_color(b, C_LIME, LV_PART_INDICATOR);
  lv_obj_set_style_radius(b, h / 2, LV_PART_MAIN); lv_obj_set_style_radius(b, h / 2, LV_PART_INDICATOR);
  return b;
}
static lv_color_t level_color(int pct) { return pct >= 90 ? C_RED : pct >= 75 ? C_AMBER : C_LIME; }

// 4-bar signal icon
static lv_obj_t *sig_icon(lv_obj_t *parent) {
  lv_obj_t *c = box(parent); lv_obj_set_size(c, 22, 16);
  for (int i = 0; i < 4; i++) {
    lv_obj_t *b = box(c); lv_obj_set_size(b, 4, 4 + i * 4); lv_obj_align(b, LV_ALIGN_BOTTOM_LEFT, i * 6, 0);
    lv_obj_set_style_radius(b, 1, 0); lv_obj_set_style_bg_opa(b, LV_OPA_COVER, 0); lv_obj_set_style_bg_color(b, C_TRACK, 0);
  }
  return c;
}
static void set_sig_icon(lv_obj_t *c, int sig) {
  int lv = sig >= 75 ? 4 : sig >= 50 ? 3 : sig >= 25 ? 2 : 1;
  for (int i = 0; i < 4; i++) lv_obj_set_style_bg_color(lv_obj_get_child(c, i), i < lv ? C_LIME : C_TRACK, 0);
}

static void send_json(JsonDocument &doc) {
  if (!Serial) return;
  serializeJson(doc, Serial); Serial.write('\n');
}
static void send_hi() {
  JsonDocument d; d["t"] = "hi"; d["dev"] = "ipnas-panel"; d["fw"] = FW_VERSION; send_json(d);
}
static int send_cmd_ctr(const char *act, const char *name) {
  JsonDocument d; int id = next_id++;
  d["t"] = "cmd"; d["id"] = id; d["op"] = "ctr"; d["act"] = act; d["name"] = name; send_json(d);
  return id;
}

// Toasts sit at the top of the screen, so they never cover the buttons.
static lv_obj_t *toast = nullptr;
static lv_timer_t *toast_tmr = nullptr;
static void toast_hide(lv_timer_t *) { if (toast) lv_obj_add_flag(toast, LV_OBJ_FLAG_HIDDEN); toast_tmr = nullptr; }
static void show_toast(const char *msg, bool ok) {
  if (!toast) {
    toast = box(lv_layer_top());
    lv_obj_set_style_radius(toast, 14, 0); lv_obj_set_style_bg_opa(toast, LV_OPA_COVER, 0);
    lv_obj_set_style_border_width(toast, 1, 0);
    lv_obj_set_style_pad_hor(toast, 16, 0); lv_obj_set_style_pad_ver(toast, 10, 0);
    lv_obj_set_size(toast, LV_SIZE_CONTENT, LV_SIZE_CONTENT);
    lv_obj_t *l = label(toast, "", &lv_font_montserrat_16, C_TEXT);
    lv_label_set_long_mode(l, LV_LABEL_LONG_WRAP); lv_obj_set_style_max_width(l, 420, 0);
  }
  lv_obj_t *l = lv_obj_get_child(toast, 0);
  char b[160]; snprintf(b, sizeof b, "%s  %s", ok ? LV_SYMBOL_OK : LV_SYMBOL_WARNING, msg);
  lv_label_set_text(l, b);
  lv_obj_set_style_bg_color(toast, ok ? C_LIME_BG : C_RED_BG, 0);
  lv_obj_set_style_border_color(toast, ok ? C_LIME : C_RED, 0);
  lv_obj_set_style_text_color(l, ok ? C_LIME : C_RED, 0);
  lv_obj_clear_flag(toast, LV_OBJ_FLAG_HIDDEN);
  lv_obj_move_foreground(toast);
  lv_obj_align(toast, LV_ALIGN_TOP_MID, 0, 8);
  if (toast_tmr) lv_timer_del(toast_tmr);
  toast_tmr = lv_timer_create(toast_hide, 3500, NULL); lv_timer_set_repeat_count(toast_tmr, 1);
}

static lv_obj_t *dim_layer() {
  lv_obj_t *o = box(lv_layer_top());
  lv_obj_set_size(o, SCR_W, SCR_H); lv_obj_set_pos(o, 0, 0);
  lv_obj_set_style_bg_color(o, lv_color_hex(0x000000), 0); lv_obj_set_style_bg_opa(o, LV_OPA_80, 0);
  lv_obj_add_flag(o, LV_OBJ_FLAG_CLICKABLE);  // swallow taps behind it
  return o;
}
static void busy_show(const char *txt) {
  if (!busy) {
    busy = dim_layer();
    lv_obj_t *sp = lv_spinner_create(busy, 1000, 60);
    lv_obj_set_size(sp, 64, 64); lv_obj_align(sp, LV_ALIGN_CENTER, 0, -44);
    lv_obj_set_style_arc_width(sp, 6, LV_PART_MAIN); lv_obj_set_style_arc_width(sp, 6, LV_PART_INDICATOR);
    lv_obj_set_style_arc_color(sp, C_LIME, LV_PART_INDICATOR); lv_obj_set_style_arc_color(sp, C_TRACK, LV_PART_MAIN);
    busy_lbl = label(busy, "", &lv_font_montserrat_16, C_TEXT);
    lv_label_set_long_mode(busy_lbl, LV_LABEL_LONG_WRAP); lv_obj_set_width(busy_lbl, 420);
    lv_obj_set_style_text_align(busy_lbl, LV_TEXT_ALIGN_CENTER, 0);
    lv_obj_align(busy_lbl, LV_ALIGN_CENTER, 0, 44);
  }
  lv_label_set_text(busy_lbl, txt);
  lv_obj_clear_flag(busy, LV_OBJ_FLAG_HIDDEN); lv_obj_move_foreground(busy);
}
static void busy_hide() { if (busy) lv_obj_add_flag(busy, LV_OBJ_FLAG_HIDDEN); }

static void scan_cb(lv_event_t *);
static void show_page(int p) {
  cur_page = p;
  for (int i = 0; i < 4; i++) {
    bool on = i == p;
    if (on) lv_obj_clear_flag(page[i], LV_OBJ_FLAG_HIDDEN); else lv_obj_add_flag(page[i], LV_OBJ_FLAG_HIDDEN);
    lv_obj_set_style_bg_opa(nav_pill[i], on ? LV_OPA_COVER : LV_OPA_TRANSP, 0);
    lv_obj_set_style_text_color(lv_obj_get_child(nav_pill[i], 0), on ? C_BG : C_DIM, 0);
    lv_obj_set_style_text_color(lv_obj_get_child(nav_btn[i], 1), on ? C_TEXT : C_DIM, 0);
  }
  // Wi-Fi page: look for networks right away (not more than every 30 s)
  if (p == 2 && linked && !scan_until && (last_scan == 0 || millis() - last_scan > 30000)) scan_cb(NULL);
}
static void nav_cb(lv_event_t *e) { show_page((int)(intptr_t)lv_event_get_user_data(e)); }

static Ctr *find_ctr(const char *name) {
  for (int i = 0; i < n_ctr; i++) if (!strcmp(ctrs[i].name, name)) return &ctrs[i];
  return nullptr;
}
static void dlg_close() { if (dlg) { lv_obj_del(dlg); dlg = nullptr; dlg_name[0] = 0; } }
static void dlg_close_cb(lv_event_t *) { dlg_close(); }
static void show_if(lv_obj_t *o, bool on) { if (on) lv_obj_clear_flag(o, LV_OBJ_FLAG_HIDDEN); else lv_obj_add_flag(o, LV_OBJ_FLAG_HIDDEN); }

static void dlg_refresh() {
  if (!dlg) return;
  Ctr *c = find_ctr(dlg_name);
  bool working = pend_id != 0 && !pend_wifi;
  if (!c) {
    set_chip(dlg_chip, "Removed", C_DIM, C_BTN);
    show_if(dlg_start, false); show_if(dlg_pause, false); show_if(dlg_restart, false); show_if(dlg_stop, false); show_if(dlg_del, false);
    return;
  }
  bool run = !strcmp(c->state, "running"), paused = !strcmp(c->state, "paused"), restarting = !strcmp(c->state, "restarting");
  if (working) set_chip(dlg_chip, "Working...", C_AMBER, C_AMBER_BG); else set_state_chip(dlg_chip, c->state);
  lv_label_set_text(dlg_status, c->status);
  char b[64], u[20], l[20];
  snprintf(b, sizeof b, "%.1f %%", c->cpu); lv_label_set_text(dlg_cpu, b);
  lv_bar_set_value(dlg_cpu_bar, constrain((int)(c->cpu * 10), 0, 1000), LV_ANIM_OFF);
  if (c->ml && (run || paused)) {
    fmt_bytes(u, sizeof u, c->mu); fmt_bytes(l, sizeof l, c->ml); snprintf(b, sizeof b, "%s / %s", u, l);
    lv_bar_set_value(dlg_ram_bar, (int)(1000.0 * c->mu / c->ml), LV_ANIM_OFF);
  } else { snprintf(b, sizeof b, "-"); lv_bar_set_value(dlg_ram_bar, 0, LV_ANIM_OFF); }
  lv_label_set_text(dlg_ram, b);
  // only the actions that make sense right now
  show_if(dlg_start, !run && !paused && !restarting);
  show_if(dlg_pause, run || paused);
  show_if(dlg_restart, run);
  show_if(dlg_stop, run || paused || restarting);
  show_if(dlg_del, true);
  lv_label_set_text(lv_obj_get_child(dlg_pause, 0), paused ? LV_SYMBOL_PLAY : LV_SYMBOL_PAUSE);
  lv_label_set_text(lv_obj_get_child(dlg_pause, 1), paused ? "Resume" : "Pause");
  lv_obj_t *all[5] = {dlg_start, dlg_pause, dlg_restart, dlg_stop, dlg_del};
  for (int i = 0; i < 5; i++) { if (working) lv_obj_add_state(all[i], LV_STATE_DISABLED); else lv_obj_clear_state(all[i], LV_STATE_DISABLED); }
}

static void run_ctr_action(const char *act, const char *verb) {
  if (!dlg_name[0] || pend_id) return;
  pend_id = send_cmd_ctr(act, dlg_name); pend_until = millis() + 95000; pend_wifi = false;
  char b[96]; snprintf(b, sizeof b, "%s %s...", verb, dlg_name); show_toast(b, true);
  dlg_refresh();
}
static void act_cb(lv_event_t *e) {
  int a = (int)(intptr_t)lv_event_get_user_data(e);
  Ctr *c = find_ctr(dlg_name);
  if (a == 0) run_ctr_action("start", "Starting");
  else if (a == 1) run_ctr_action("stop", "Stopping");
  else if (a == 2) { if (c && !strcmp(c->state, "paused")) run_ctr_action("unpause", "Resuming"); else run_ctr_action("pause", "Pausing"); }
  else if (a == 3) run_ctr_action("restart", "Restarting");
}

static lv_obj_t *confirm = nullptr;
static void confirm_close() { if (confirm) { lv_obj_del(confirm); confirm = nullptr; } }
static void confirm_no_cb(lv_event_t *) { confirm_close(); }
static void confirm_del_cb(lv_event_t *) { confirm_close(); run_ctr_action("rm", "Deleting"); }
static lv_obj_t *dialog(const char *title, const char *text, lv_color_t accent) {  // centred card on a dim layer
  confirm_close();
  confirm = dim_layer();
  lv_obj_t *c = card(confirm, 60, 70, 360, 180);
  lv_obj_set_style_border_color(c, accent, 0);
  lv_obj_t *t = label(c, title, &lv_font_montserrat_20, C_TEXT); lv_obj_set_width(t, 334); lv_label_set_long_mode(t, LV_LABEL_LONG_DOT);
  lv_obj_t *s = label(c, text, &lv_font_montserrat_14, C_DIM); lv_obj_set_pos(s, 0, 34);
  lv_obj_set_width(s, 334); lv_label_set_long_mode(s, LV_LABEL_LONG_WRAP);
  return c;
}
static void ask_delete_cb(lv_event_t *) {
  if (!dlg_name[0] || pend_id) return;
  char b[96]; snprintf(b, sizeof b, "Delete %s?", dlg_name);
  lv_obj_t *c = dialog(b, "It is removed from the Pi. Its image and data folders stay.", C_RED);
  lv_obj_t *n = button(c, "Cancel", C_BTN, C_TEXT, 161, 48, confirm_no_cb, NULL); lv_obj_align(n, LV_ALIGN_BOTTOM_LEFT, 0, 0);
  lv_obj_t *y = button(c, LV_SYMBOL_TRASH "  Delete", C_RED, C_TEXT, 161, 48, confirm_del_cb, NULL); lv_obj_align(y, LV_ALIGN_BOTTOM_RIGHT, 0, 0);
}

static lv_obj_t *full_overlay() {
  lv_obj_t *o = box(lv_layer_top());
  lv_obj_set_size(o, SCR_W, SCR_H); lv_obj_set_pos(o, 0, 0);
  lv_obj_set_style_bg_color(o, C_BG, 0); lv_obj_set_style_bg_opa(o, LV_OPA_COVER, 0);
  lv_obj_add_flag(o, LV_OBJ_FLAG_CLICKABLE);
  return o;
}

static void open_detail(const char *name) {
  dlg_close();
  Ctr *c = find_ctr(name); if (!c) return;
  copy_str(dlg_name, sizeof dlg_name, name);
  dlg = full_overlay();

  lv_obj_t *back = button(dlg, LV_SYMBOL_LEFT, C_BTN, C_TEXT, 44, 44, dlg_close_cb, NULL); lv_obj_set_pos(back, 12, 10);
  lv_obj_t *t = label(dlg, name, &lv_font_montserrat_24, C_TEXT); lv_obj_set_pos(t, 68, 8);
  lv_obj_set_width(t, 270); lv_label_set_long_mode(t, LV_LABEL_LONG_DOT);
  lv_obj_t *im = label(dlg, c->image, &lv_font_montserrat_12, C_DIM); lv_obj_set_pos(im, 68, 37);
  lv_obj_set_width(im, 280); lv_label_set_long_mode(im, LV_LABEL_LONG_DOT);
  dlg_chip = chip(dlg); lv_obj_align(dlg_chip, LV_ALIGN_TOP_RIGHT, -14, 21);

  lv_obj_t *k = card(dlg, 12, 64, 456, 108);
  dlg_status = caption(k, ""); lv_obj_set_pos(dlg_status, 0, 0);
  lv_obj_t *l1 = label(k, "CPU", &lv_font_montserrat_14, C_DIM); lv_obj_set_pos(l1, 0, 28);
  dlg_cpu_bar = hbar(k, 52, 33, 240, 8);
  dlg_cpu = label(k, "", &lv_font_montserrat_16, C_TEXT); lv_obj_align(dlg_cpu, LV_ALIGN_TOP_RIGHT, 0, 26);
  lv_obj_t *l2 = label(k, "RAM", &lv_font_montserrat_14, C_DIM); lv_obj_set_pos(l2, 0, 60);
  dlg_ram_bar = hbar(k, 52, 65, 240, 8);
  dlg_ram = label(k, "", &lv_font_montserrat_16, C_TEXT); lv_obj_align(dlg_ram, LV_ALIGN_TOP_RIGHT, 0, 58);

  lv_obj_t *row = box(dlg);
  lv_obj_set_pos(row, 12, 182); lv_obj_set_size(row, 456, 72);
  lv_obj_set_flex_flow(row, LV_FLEX_FLOW_ROW); lv_obj_set_style_pad_column(row, 8, 0);
  dlg_start   = tile_btn(row, LV_SYMBOL_PLAY, "Start", C_LIME, C_BG, act_cb, (void *)0);
  dlg_pause   = tile_btn(row, LV_SYMBOL_PAUSE, "Pause", C_BTN, C_TEXT, act_cb, (void *)2);
  dlg_restart = tile_btn(row, LV_SYMBOL_REFRESH, "Restart", C_BTN, C_TEXT, act_cb, (void *)3);
  dlg_stop    = tile_btn(row, LV_SYMBOL_STOP, "Stop", C_BTN, C_TEXT, act_cb, (void *)1);
  dlg_del = button(dlg, LV_SYMBOL_TRASH "  Delete container", C_BG, C_RED, 456, 46, ask_delete_cb, NULL);
  lv_obj_set_pos(dlg_del, 12, 264);
  lv_obj_set_style_border_width(dlg_del, 1, 0); lv_obj_set_style_border_color(dlg_del, lv_color_hex(0x5A2626), 0);
  lv_obj_set_style_text_font(lv_obj_get_child(dlg_del, 0), &lv_font_montserrat_14, 0);
  dlg_refresh();
}
static void row_cb(lv_event_t *e) {
  int i = (int)(intptr_t)lv_event_get_user_data(e);
  if (i < n_ctr) open_detail(ctrs[i].name);
}

static void apps_refresh() {
  while (n_rows < n_ctr && n_rows < MAX_CTR) {
    lv_obj_t *r = lv_obj_create(apps_list);
    lv_obj_set_size(r, lv_pct(100), 62);
    lv_obj_set_style_bg_color(r, C_CARD, 0); lv_obj_set_style_bg_color(r, C_BTN, LV_STATE_PRESSED);
    lv_obj_set_style_radius(r, 16, 0); lv_obj_set_style_border_width(r, 1, 0); lv_obj_set_style_border_color(r, C_LINE, 0);
    lv_obj_set_style_pad_all(r, 10, 0);
    lv_obj_clear_flag(r, LV_OBJ_FLAG_SCROLLABLE); lv_obj_add_flag(r, LV_OBJ_FLAG_CLICKABLE);
    lv_obj_add_event_cb(r, row_cb, LV_EVENT_CLICKED, (void *)(intptr_t)n_rows);
    lv_obj_t *ic = box(r); lv_obj_set_size(ic, 40, 40); lv_obj_align(ic, LV_ALIGN_LEFT_MID, 0, 0);   // 0 initial tile
    lv_obj_set_style_radius(ic, 12, 0); lv_obj_set_style_bg_opa(ic, LV_OPA_COVER, 0); lv_obj_set_style_bg_color(ic, C_BTN, 0);
    lv_obj_t *il = label(ic, "", &lv_font_montserrat_20, C_LIME); lv_obj_center(il);
    lv_obj_t *nm = label(r, "", &lv_font_montserrat_16, C_TEXT); lv_obj_set_pos(nm, 52, 0);        // 1 name
    lv_obj_set_width(nm, 180); lv_label_set_long_mode(nm, LV_LABEL_LONG_DOT);
    lv_obj_t *st = label(r, "", &lv_font_montserrat_12, C_DIM); lv_obj_set_pos(st, 52, 22);         // 2 status
    lv_obj_set_width(st, 180); lv_label_set_long_mode(st, LV_LABEL_LONG_DOT);
    lv_obj_t *ch = chip(r); lv_obj_align(ch, LV_ALIGN_TOP_RIGHT, 0, -2);                            // 3 state chip
    lv_obj_t *mt = label(r, "", &lv_font_montserrat_12, C_DIM); lv_obj_align(mt, LV_ALIGN_BOTTOM_RIGHT, 0, 2);  // 4 usage
    app_row[n_rows++] = r;
  }
  while (n_rows > n_ctr) { lv_obj_del(app_row[--n_rows]); }
  int running = 0;
  for (int i = 0; i < n_rows; i++) {
    Ctr &c = ctrs[i];
    bool run = !strcmp(c.state, "running");
    running += run;
    lv_obj_t *r = app_row[i];
    char ini[2] = {(char)toupper((unsigned char)c.name[0]), 0};
    lv_obj_t *il = lv_obj_get_child(lv_obj_get_child(r, 0), 0);
    lv_label_set_text(il, ini); lv_obj_set_style_text_color(il, run ? C_LIME : C_FAINT, 0);
    lv_label_set_text(lv_obj_get_child(r, 1), c.name);
    lv_label_set_text(lv_obj_get_child(r, 2), c.status);
    set_state_chip(lv_obj_get_child(r, 3), c.state);
    char b[40], m[20];
    if (run) { fmt_bytes(m, sizeof m, c.mu); snprintf(b, sizeof b, "CPU %.1f%%   RAM %s", c.cpu, m); }
    else b[0] = 0;
    lv_label_set_text(lv_obj_get_child(r, 4), b);
    lv_obj_align(lv_obj_get_child(r, 4), LV_ALIGN_BOTTOM_RIGHT, 0, 2);
    lv_obj_align(lv_obj_get_child(r, 3), LV_ALIGN_TOP_RIGHT, 0, run ? -2 : 8);
  }
  char b[48]; snprintf(b, sizeof b, "%d of %d running", running, n_ctr);
  lv_label_set_text(apps_count, b);
  show_if(apps_empty, n_ctr == 0);
  // badge on the Apps tab
  lv_label_set_text_fmt(lv_obj_get_child(nav_badge, 0), "%d", running);
  show_if(nav_badge, running > 0);
}

static void scan_done_ui() {
  scan_until = 0;
  lv_label_set_text(wifi_scan_lbl, LV_SYMBOL_REFRESH "  Scan"); lv_obj_clear_state(wifi_scan_btn, LV_STATE_DISABLED);
}
static void scan_cb(lv_event_t *) {
  JsonDocument d; d["t"] = "cmd"; d["id"] = next_id++; d["op"] = "wifi_scan"; send_json(d);
  scan_until = millis() + 40000; last_scan = millis();
  lv_label_set_text(wifi_scan_lbl, "Scanning...");
  lv_obj_add_state(wifi_scan_btn, LV_STATE_DISABLED);
  if (!n_net) { lv_label_set_text(wifi_hint, "Looking for networks near the Pi..."); show_if(wifi_hint, true); }
}
static void kbd_close() { if (kbd_scr) { lv_obj_del(kbd_scr); kbd_scr = nullptr; } }
static void wifi_connect(const char *ssid, const char *psk) {
  JsonDocument d; int id = next_id++;
  d["t"] = "cmd"; d["id"] = id; d["op"] = "wifi_connect"; d["ssid"] = ssid; d["psk"] = psk; send_json(d);
  pend_id = id; pend_until = millis() + 100000; pend_wifi = true;
  char b[180]; snprintf(b, sizeof b, "Connecting the Pi to %s\nThis can take up to a minute.\nIf it fails, the Pi goes back to %s.", ssid, cur_ssid[0] ? cur_ssid : "its old network");
  busy_show(b);
}
static void kbd_event(lv_event_t *e) {
  lv_event_code_t code = lv_event_get_code(e);
  if (code == LV_EVENT_READY) {
    const char *pw = lv_textarea_get_text(kbd_ta);
    if (strlen(pw) < 8) { show_toast("Wi-Fi passwords have at least 8 characters", false); return; }
    char ssid[33], psk[64]; copy_str(ssid, sizeof ssid, kbd_ssid); copy_str(psk, sizeof psk, pw);
    kbd_close(); wifi_connect(ssid, psk);
  } else if (code == LV_EVENT_CANCEL) kbd_close();
}
static void kbd_draw_cb(lv_event_t *e) {  // the OK key is lime, so "connect" is obvious
  lv_obj_draw_part_dsc_t *dsc = lv_event_get_draw_part_dsc(e);
  if (dsc->class_p != &lv_btnmatrix_class || dsc->type != LV_BTNMATRIX_DRAW_PART_BTN) return;
  const char *t = lv_btnmatrix_get_btn_text(lv_event_get_target(e), dsc->id);
  if (!t) return;
  if (!strcmp(t, LV_SYMBOL_OK)) { dsc->rect_dsc->bg_color = C_LIME; dsc->label_dsc->color = C_BG; }
  else if (!strcmp(t, "ABC") || !strcmp(t, "abc") || !strcmp(t, "1#")) dsc->label_dsc->font = &lv_font_montserrat_14;
}
static void kbd_cancel_cb(lv_event_t *) { kbd_close(); }
static void kbd_eye_cb(lv_event_t *) {
  bool pw = lv_textarea_get_password_mode(kbd_ta);
  lv_textarea_set_password_mode(kbd_ta, !pw);
  lv_label_set_text(lv_obj_get_child(kbd_eye, 0), pw ? LV_SYMBOL_EYE_CLOSE : LV_SYMBOL_EYE_OPEN);
}

#define KF (LV_BTNMATRIX_CTRL_POPOVER)
#define KC (LV_KEYBOARD_CTRL_BTN_FLAGS)
static const char *kb_lower[] = {
  "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "\n",
  "q", "w", "e", "r", "t", "y", "u", "i", "o", "p", "\n",
  "a", "s", "d", "f", "g", "h", "j", "k", "l", LV_SYMBOL_BACKSPACE, "\n",
  "ABC", "z", "x", "c", "v", "b", "n", "m", "_", "@", "\n",
  "1#", ".", " ", "-", LV_SYMBOL_OK, ""};
static const char *kb_upper[] = {
  "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "\n",
  "Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P", "\n",
  "A", "S", "D", "F", "G", "H", "J", "K", "L", LV_SYMBOL_BACKSPACE, "\n",
  "abc", "Z", "X", "C", "V", "B", "N", "M", "_", "@", "\n",
  "1#", ".", " ", "-", LV_SYMBOL_OK, ""};
static const char *kb_special[] = {
  "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "\n",
  "!", "@", "#", "$", "%", "^", "&", "*", "(", ")", "\n",
  "-", "_", "=", "+", "[", "]", "{", "}", ";", LV_SYMBOL_BACKSPACE, "\n",
  "abc", ":", "'", "\"", ",", ".", "/", "?", "\\", "|", "\n",
  "ABC", "<", ">", "~", "`", " ", LV_SYMBOL_OK, ""};
static const lv_btnmatrix_ctrl_t kb_ctrl_letters[] = {
  4 | KF, 4 | KF, 4 | KF, 4 | KF, 4 | KF, 4 | KF, 4 | KF, 4 | KF, 4 | KF, 4 | KF,
  4 | KF, 4 | KF, 4 | KF, 4 | KF, 4 | KF, 4 | KF, 4 | KF, 4 | KF, 4 | KF, 4 | KF,
  4 | KF, 4 | KF, 4 | KF, 4 | KF, 4 | KF, 4 | KF, 4 | KF, 4 | KF, 4 | KF, 4 | KC,
  4 | KC, 4 | KF, 4 | KF, 4 | KF, 4 | KF, 4 | KF, 4 | KF, 4 | KF, 4 | KF, 4 | KF,
  4 | KC, 3 | KF, 7, 3 | KF, 6 | KC};
static const lv_btnmatrix_ctrl_t kb_ctrl_special[] = {
  4 | KF, 4 | KF, 4 | KF, 4 | KF, 4 | KF, 4 | KF, 4 | KF, 4 | KF, 4 | KF, 4 | KF,
  4 | KF, 4 | KF, 4 | KF, 4 | KF, 4 | KF, 4 | KF, 4 | KF, 4 | KF, 4 | KF, 4 | KF,
  4 | KF, 4 | KF, 4 | KF, 4 | KF, 4 | KF, 4 | KF, 4 | KF, 4 | KF, 4 | KF, 4 | KC,
  4 | KC, 4 | KF, 4 | KF, 4 | KF, 4 | KF, 4 | KF, 4 | KF, 4 | KF, 4 | KF, 4 | KF,
  4 | KC, 2 | KF, 2 | KF, 2 | KF, 2 | KF, 5, 5 | KC};

static void open_keyboard(const char *ssid) {
  kbd_close();
  copy_str(kbd_ssid, sizeof kbd_ssid, ssid);
  kbd_scr = full_overlay();

  lv_obj_t *x = button(kbd_scr, LV_SYMBOL_CLOSE, C_BTN, C_TEXT, 40, 40, kbd_cancel_cb, NULL); lv_obj_set_pos(x, 8, 6);
  lv_obj_t *cap = caption(kbd_scr, "PASSWORD FOR"); lv_obj_set_pos(cap, 60, 6);
  lv_obj_t *t = label(kbd_scr, ssid, &lv_font_montserrat_18, C_LIME); lv_obj_set_pos(t, 60, 22);
  lv_obj_set_width(t, 400); lv_label_set_long_mode(t, LV_LABEL_LONG_DOT);

  kbd_ta = lv_textarea_create(kbd_scr);
  lv_obj_set_pos(kbd_ta, 8, 54); lv_obj_set_size(kbd_ta, 414, 44);
  lv_textarea_set_one_line(kbd_ta, true); lv_textarea_set_password_mode(kbd_ta, true);
  lv_textarea_set_max_length(kbd_ta, 63); lv_textarea_set_placeholder_text(kbd_ta, "Type the Wi-Fi password");
  lv_obj_set_style_text_font(kbd_ta, &lv_font_montserrat_20, 0);
  lv_obj_set_style_bg_color(kbd_ta, C_CARD, 0); lv_obj_set_style_radius(kbd_ta, 14, 0);
  lv_obj_set_style_border_color(kbd_ta, C_LIME, 0); lv_obj_set_style_border_width(kbd_ta, 2, 0);
  lv_obj_set_style_pad_hor(kbd_ta, 14, 0); lv_obj_set_style_pad_ver(kbd_ta, 9, 0);
  lv_obj_set_style_text_color(kbd_ta, C_TEXT, 0);
  lv_obj_add_state(kbd_ta, LV_STATE_FOCUSED);
  kbd_eye = button(kbd_scr, LV_SYMBOL_EYE_OPEN, C_BTN, C_TEXT, 44, 44, kbd_eye_cb, NULL); lv_obj_set_pos(kbd_eye, 428, 54);

  lv_obj_t *kb = lv_keyboard_create(kbd_scr);
  lv_obj_set_size(kb, SCR_W, 214); lv_obj_align(kb, LV_ALIGN_BOTTOM_MID, 0, 0);
  lv_keyboard_set_map(kb, LV_KEYBOARD_MODE_TEXT_LOWER, kb_lower, kb_ctrl_letters);
  lv_keyboard_set_map(kb, LV_KEYBOARD_MODE_TEXT_UPPER, kb_upper, kb_ctrl_letters);
  lv_keyboard_set_map(kb, LV_KEYBOARD_MODE_SPECIAL, kb_special, kb_ctrl_special);
  lv_keyboard_set_mode(kb, LV_KEYBOARD_MODE_TEXT_LOWER);
  lv_keyboard_set_popovers(kb, true);
  lv_keyboard_set_textarea(kb, kbd_ta);
  lv_obj_set_style_bg_color(kb, C_BG, 0); lv_obj_set_style_border_width(kb, 0, 0);
  lv_obj_set_style_pad_all(kb, 5, 0); lv_obj_set_style_pad_gap(kb, 5, 0); lv_obj_set_style_radius(kb, 0, 0);
  lv_obj_set_style_bg_color(kb, lv_color_hex(0x262A30), LV_PART_ITEMS);
  lv_obj_set_style_text_color(kb, C_TEXT, LV_PART_ITEMS);
  lv_obj_set_style_text_font(kb, &lv_font_montserrat_18, LV_PART_ITEMS);
  lv_obj_set_style_radius(kb, 8, LV_PART_ITEMS); lv_obj_set_style_shadow_width(kb, 0, LV_PART_ITEMS);
  lv_obj_set_style_border_width(kb, 0, LV_PART_ITEMS);
  lv_obj_set_style_bg_color(kb, lv_color_hex(0x16191D), LV_PART_ITEMS | LV_STATE_CHECKED);
  lv_obj_set_style_text_color(kb, C_DIM, LV_PART_ITEMS | LV_STATE_CHECKED);
  lv_obj_set_style_bg_color(kb, C_LIME, LV_PART_ITEMS | LV_STATE_PRESSED);
  lv_obj_set_style_text_color(kb, C_BG, LV_PART_ITEMS | LV_STATE_PRESSED);
  lv_obj_add_event_cb(kb, kbd_event, LV_EVENT_READY, NULL);
  lv_obj_add_event_cb(kb, kbd_event, LV_EVENT_CANCEL, NULL);
  lv_obj_add_event_cb(kb, kbd_draw_cb, LV_EVENT_DRAW_PART_BEGIN, NULL);
}

static char open_ssid[33];
static void open_yes_cb(lv_event_t *) { confirm_close(); wifi_connect(open_ssid, ""); }

static bool net_is_open(const Net &n) { return !strcmp(n.sec, "open") || !strcmp(n.sec, "--") || !n.sec[0]; }
static void net_cb(lv_event_t *e) {
  int i = (int)(intptr_t)lv_event_get_user_data(e);
  if (i >= n_net || pend_id) return;
  Net &n = nets[i];
  if (n.cur) { show_toast("The Pi is already on this network", true); return; }
  if (!net_is_open(n)) { open_keyboard(n.ssid); return; }
  copy_str(open_ssid, sizeof open_ssid, n.ssid);
  char b[80]; snprintf(b, sizeof b, "Join %s?", n.ssid);
  lv_obj_t *c = dialog(b, "This network has no password. Anyone nearby can see its traffic.", C_LIME);
  lv_obj_t *no = button(c, "Cancel", C_BTN, C_TEXT, 161, 48, confirm_no_cb, NULL); lv_obj_align(no, LV_ALIGN_BOTTOM_LEFT, 0, 0);
  lv_obj_t *yes = button(c, "Join", C_LIME, C_BG, 161, 48, open_yes_cb, NULL); lv_obj_align(yes, LV_ALIGN_BOTTOM_RIGHT, 0, 0);
}

static void wifi_list_refresh() {
  while (n_net_rows < n_net) {
    lv_obj_t *r = lv_obj_create(wifi_list);
    lv_obj_set_size(r, lv_pct(100), 48);
    lv_obj_set_style_bg_color(r, C_CARD, 0); lv_obj_set_style_bg_color(r, C_BTN, LV_STATE_PRESSED);
    lv_obj_set_style_radius(r, 14, 0); lv_obj_set_style_border_width(r, 1, 0); lv_obj_set_style_border_color(r, C_LINE, 0);
    lv_obj_set_style_pad_hor(r, 14, 0); lv_obj_set_style_pad_ver(r, 0, 0);
    lv_obj_clear_flag(r, LV_OBJ_FLAG_SCROLLABLE); lv_obj_add_flag(r, LV_OBJ_FLAG_CLICKABLE);
    lv_obj_add_event_cb(r, net_cb, LV_EVENT_CLICKED, (void *)(intptr_t)n_net_rows);
    lv_obj_t *sg = sig_icon(r); lv_obj_align(sg, LV_ALIGN_LEFT_MID, 0, -1);                         // 0
    lv_obj_t *nm = label(r, "", &lv_font_montserrat_16, C_TEXT); lv_obj_align(nm, LV_ALIGN_LEFT_MID, 36, 0);  // 1
    lv_obj_set_width(nm, 220); lv_label_set_long_mode(nm, LV_LABEL_LONG_DOT);
    lv_obj_t *ch = chip(r); lv_obj_align(ch, LV_ALIGN_RIGHT_MID, 0, 0);                              // 2
    net_row[n_net_rows++] = r;
  }
  while (n_net_rows > n_net) lv_obj_del(net_row[--n_net_rows]);
  for (int i = 0; i < n_net_rows; i++) {
    Net &n = nets[i]; lv_obj_t *r = net_row[i];
    lv_obj_set_style_border_color(r, n.cur ? C_LIME : C_LINE, 0);
    set_sig_icon(lv_obj_get_child(r, 0), n.sig);
    lv_label_set_text(lv_obj_get_child(r, 1), n.ssid);
    lv_obj_t *ch = lv_obj_get_child(r, 2);
    if (n.cur) set_chip(ch, "Connected", C_LIME, C_LIME_BG);
    else if (net_is_open(n)) set_chip(ch, "Open", C_AMBER, C_AMBER_BG);
    else set_chip(ch, "Secured", C_DIM, C_BTN);
    lv_obj_align(ch, LV_ALIGN_RIGHT_MID, 0, 0);
  }
  show_if(wifi_hint, n_net == 0);
}

static void bright_cb(lv_event_t *e) {
  brightness = lv_slider_get_value(lv_event_get_target(e)); set_backlight(brightness);
  if (lv_event_get_code(e) == LV_EVENT_RELEASED) prefs.putInt("bri", brightness);
}
static void flip_cb(lv_event_t *e) {
  flip = lv_obj_has_state(lv_event_get_target(e), LV_STATE_CHECKED);
  prefs.putBool("flip", flip);
  lv_obj_invalidate(lv_scr_act());
}
static void settings_refresh() {
  char b[400];
  snprintf(b, sizeof b, FW_VERSION "\n%s\n%s\n%s\n%s\n%s",
           pi_host[0] ? pi_host : "-", pi_model[0] ? pi_model : "-", pi_os[0] ? pi_os : "-", pi_ip[0] ? pi_ip : "-", pi_agent[0] ? pi_agent : "-");
  lv_label_set_text(set_info, b);
}

static lv_obj_t *new_screen() {
  lv_obj_t *s = lv_obj_create(NULL);
  lv_obj_set_style_bg_color(s, C_BG, 0); lv_obj_set_style_bg_opa(s, LV_OPA_COVER, 0);
  lv_obj_clear_flag(s, LV_OBJ_FLAG_SCROLLABLE);
  return s;
}
#define PG_X 80
#define PG_Y 50
#define PG_W (SCR_W - PG_X - 8)   // 392
#define PG_H (SCR_H - PG_Y - 8)   // 262
static lv_obj_t *new_page() {
  lv_obj_t *p = box(scr_main);
  lv_obj_set_pos(p, PG_X, PG_Y); lv_obj_set_size(p, PG_W, PG_H);
  return p;
}

static void build_wait() {
  scr_wait = new_screen();
  lv_obj_t *lg = lv_img_create(scr_wait); lv_img_set_src(lg, &img_logo_96); lv_obj_align(lg, LV_ALIGN_TOP_MID, 0, 34);
  lv_obj_t *t = label(scr_wait, "IP NAS", &lv_font_montserrat_40, C_TEXT); lv_obj_align(t, LV_ALIGN_TOP_MID, 0, 140);
  lv_obj_t *sp = lv_spinner_create(scr_wait, 1200, 70);
  lv_obj_set_size(sp, 30, 30); lv_obj_align(sp, LV_ALIGN_TOP_MID, -112, 216);
  lv_obj_set_style_arc_width(sp, 4, LV_PART_MAIN); lv_obj_set_style_arc_width(sp, 4, LV_PART_INDICATOR);
  lv_obj_set_style_arc_color(sp, C_LIME, LV_PART_INDICATOR); lv_obj_set_style_arc_color(sp, C_TRACK, LV_PART_MAIN);
  lv_obj_t *w = label(scr_wait, "Waiting for the NAS", &lv_font_montserrat_20, C_LIME); lv_obj_align(w, LV_ALIGN_TOP_MID, 20, 219);
  lv_obj_t *h = label(scr_wait, "Plug this screen into a USB port of the Raspberry Pi", &lv_font_montserrat_14, C_DIM);
  lv_obj_align(h, LV_ALIGN_TOP_MID, 0, 262);
  lv_obj_t *v = label(scr_wait, "firmware " FW_VERSION, &lv_font_montserrat_12, C_FAINT); lv_obj_align(v, LV_ALIGN_BOTTOM_RIGHT, -8, -6);
}

static void build_home(lv_obj_t *p) {
  // row 1: three gauges
  const char *names[3] = {"CPU", "MEMORY", "TEMPERATURE"};
  lv_obj_t **arcs[3] = {&arc_cpu, &arc_ram, &arc_tmp};
  lv_obj_t **vals[3] = {&lbl_cpu, &lbl_ram, &lbl_tmp};
  const int tw[3] = {125, 125, 126};
  int x = 0;
  for (int i = 0; i < 3; i++) {
    lv_obj_t *c = card(p, x, 0, tw[i], 124); x += tw[i] + 8;
    lv_obj_t *n = caption(c, names[i]); lv_obj_set_pos(n, 0, -2);
    *arcs[i] = arc_gauge(c, 84, vals[i]); lv_obj_align(*arcs[i], LV_ALIGN_BOTTOM_MID, 0, 12);
  }
  sub_ram = label(arc_ram, "", &lv_font_montserrat_12, C_DIM); lv_obj_align(sub_ram, LV_ALIGN_CENTER, 0, 18);
  lv_arc_set_range(arc_tmp, 30, 85);

  // row 2: storage + network + uptime
  lv_obj_t *s = card(p, 0, 132, 250, 130);
  lv_obj_t *st = caption(s, "STORAGE"); lv_obj_set_pos(st, 0, -2);
  const char *dn[3] = {"HDD 1", "HDD 2", "SD"};
  for (int i = 0; i < 3; i++) {
    int y = 20 + i * 32;
    disk_lbl[i] = label(s, dn[i], &lv_font_montserrat_14, C_TEXT); lv_obj_set_pos(disk_lbl[i], 0, y);
    disk_val[i] = label(s, "-", &lv_font_montserrat_12, C_DIM); lv_obj_align(disk_val[i], LV_ALIGN_TOP_RIGHT, 0, y + 1);
    disk_bar[i] = hbar(s, 0, y + 19, 226, 6);
  }
  lv_obj_t *n = card(p, 258, 132, 134, 61);
  lv_obj_t *nc = caption(n, "NETWORK"); lv_obj_set_pos(nc, 0, -4);
  lv_obj_t *d1 = label(n, LV_SYMBOL_DOWN, &lv_font_montserrat_12, C_LIME); lv_obj_set_pos(d1, 0, 13);
  lbl_rx = label(n, "-", &lv_font_montserrat_14, C_TEXT); lv_obj_set_pos(lbl_rx, 18, 11);
  lv_obj_t *u1 = label(n, LV_SYMBOL_UP, &lv_font_montserrat_12, C_DIM); lv_obj_set_pos(u1, 0, 30);
  lbl_tx = label(n, "-", &lv_font_montserrat_14, C_TEXT); lv_obj_set_pos(lbl_tx, 18, 28);
  lv_obj_set_style_pad_ver(n, 10, 0);
  lv_obj_t *u = card(p, 258, 201, 134, 61);
  lv_obj_set_style_pad_ver(u, 10, 0);
  lv_obj_t *uc = caption(u, "UPTIME"); lv_obj_set_pos(uc, 0, -4);
  lbl_up = label(u, "-", &lv_font_montserrat_20, C_TEXT); lv_obj_set_pos(lbl_up, 0, 14);
}

static void build_apps(lv_obj_t *p) {
  lv_obj_t *t = label(p, "Apps", &lv_font_montserrat_24, C_TEXT); lv_obj_set_pos(t, 2, -2);
  apps_count = label(p, "", &lv_font_montserrat_14, C_DIM); lv_obj_align(apps_count, LV_ALIGN_TOP_RIGHT, -2, 6);
  apps_list = box(p);
  lv_obj_add_flag(apps_list, LV_OBJ_FLAG_SCROLLABLE);
  lv_obj_set_pos(apps_list, 0, 36); lv_obj_set_size(apps_list, PG_W, PG_H - 36);
  lv_obj_set_style_pad_row(apps_list, 8, 0);
  lv_obj_set_flex_flow(apps_list, LV_FLEX_FLOW_COLUMN);
  lv_obj_set_scrollbar_mode(apps_list, LV_SCROLLBAR_MODE_OFF);
  apps_empty = label(p, "No containers on the Pi yet.", &lv_font_montserrat_14, C_DIM); lv_obj_set_pos(apps_empty, 4, 48);
}

static void build_wifi(lv_obj_t *p) {
  lv_obj_t *c = card(p, 0, 0, PG_W, 70);
  wifi_icon = box(c); lv_obj_set_size(wifi_icon, 44, 44); lv_obj_align(wifi_icon, LV_ALIGN_LEFT_MID, 0, 0);
  lv_obj_set_style_radius(wifi_icon, 14, 0); lv_obj_set_style_bg_opa(wifi_icon, LV_OPA_COVER, 0); lv_obj_set_style_bg_color(wifi_icon, C_LIME_BG, 0);
  lv_obj_t *ic = label(wifi_icon, LV_SYMBOL_WIFI, &lv_font_montserrat_20, C_LIME); lv_obj_center(ic);
  wifi_cur = label(c, "-", &lv_font_montserrat_18, C_TEXT); lv_obj_set_pos(wifi_cur, 56, 0);
  lv_obj_set_width(wifi_cur, 180); lv_label_set_long_mode(wifi_cur, LV_LABEL_LONG_DOT);
  wifi_sub = label(c, "", &lv_font_montserrat_12, C_DIM); lv_obj_set_pos(wifi_sub, 56, 26);
  wifi_scan_btn = button(c, LV_SYMBOL_REFRESH "  Scan", C_BTN, C_LIME, 116, 44, scan_cb, NULL);
  lv_obj_align(wifi_scan_btn, LV_ALIGN_RIGHT_MID, 0, 0);
  wifi_scan_lbl = lv_obj_get_child(wifi_scan_btn, 0);
  lv_obj_t *cap = caption(p, "NETWORKS NEAR THE PI"); lv_obj_set_pos(cap, 4, 80);
  wifi_list = box(p);
  lv_obj_add_flag(wifi_list, LV_OBJ_FLAG_SCROLLABLE);
  lv_obj_set_pos(wifi_list, 0, 100); lv_obj_set_size(wifi_list, PG_W, PG_H - 100);
  lv_obj_set_style_pad_row(wifi_list, 8, 0);
  lv_obj_set_flex_flow(wifi_list, LV_FLEX_FLOW_COLUMN);
  lv_obj_set_scrollbar_mode(wifi_list, LV_SCROLLBAR_MODE_OFF);
  wifi_hint = label(p, "Tap Scan to look for networks.", &lv_font_montserrat_14, C_DIM);
  lv_obj_set_pos(wifi_hint, 4, 112);
}

static void build_settings(lv_obj_t *p) {
  lv_obj_t *c = card(p, 0, 0, PG_W, 112);
  lv_obj_t *cap = caption(c, "DISPLAY"); lv_obj_set_pos(cap, 0, -2);
  lv_obj_t *l = label(c, "Brightness", &lv_font_montserrat_16, C_TEXT); lv_obj_set_pos(l, 0, 22);
  lv_obj_t *sl = lv_slider_create(c);
  lv_obj_set_size(sl, 200, 8); lv_obj_align(sl, LV_ALIGN_TOP_RIGHT, -10, 28);
  lv_slider_set_range(sl, 15, 255); lv_slider_set_value(sl, brightness, LV_ANIM_OFF);
  lv_obj_set_style_bg_color(sl, C_TRACK, LV_PART_MAIN); lv_obj_set_style_bg_color(sl, C_LIME, LV_PART_INDICATOR);
  lv_obj_set_style_bg_color(sl, C_TEXT, LV_PART_KNOB); lv_obj_set_style_pad_all(sl, 5, LV_PART_KNOB);
  lv_obj_set_ext_click_area(sl, 16);
  lv_obj_add_event_cb(sl, bright_cb, LV_EVENT_VALUE_CHANGED, NULL);
  lv_obj_add_event_cb(sl, bright_cb, LV_EVENT_RELEASED, NULL);
  lv_obj_t *f = label(c, "Flip screen 180" "\xC2\xB0", &lv_font_montserrat_16, C_TEXT); lv_obj_set_pos(f, 0, 64);
  set_flip_sw = lv_switch_create(c); lv_obj_set_size(set_flip_sw, 50, 28); lv_obj_align(set_flip_sw, LV_ALIGN_TOP_RIGHT, 0, 60);
  lv_obj_set_style_bg_color(set_flip_sw, C_TRACK, LV_PART_MAIN);
  lv_obj_set_style_bg_color(set_flip_sw, C_LIME, LV_PART_INDICATOR | LV_STATE_CHECKED);
  if (flip) lv_obj_add_state(set_flip_sw, LV_STATE_CHECKED);
  lv_obj_add_event_cb(set_flip_sw, flip_cb, LV_EVENT_VALUE_CHANGED, NULL);
  lv_obj_t *i = card(p, 0, 120, PG_W, 142);
  lv_obj_t *cap2 = caption(i, "ABOUT"); lv_obj_set_pos(cap2, 0, -2);
  lv_obj_t *keys = label(i, "Firmware\nPi name\nModel\nSystem\nPi address\nPi agent", &lv_font_montserrat_14, C_DIM);
  lv_obj_set_style_text_line_space(keys, 2, 0); lv_obj_set_pos(keys, 0, 16);
  set_info = label(i, "", &lv_font_montserrat_14, C_TEXT);
  lv_obj_set_style_text_line_space(set_info, 2, 0); lv_obj_set_pos(set_info, 110, 16);
  lv_obj_set_width(set_info, 244); lv_label_set_long_mode(set_info, LV_LABEL_LONG_CLIP);
  settings_refresh();
}

static void build_main() {
  scr_main = new_screen();
  // top bar: brand left, Wi-Fi status + clock right
  lv_obj_t *lg = lv_img_create(scr_main); lv_img_set_src(lg, &img_logo_28); lv_obj_set_pos(lg, 26, 9);
  lv_obj_t *t = label(scr_main, "IP NAS", &lv_font_montserrat_20, C_TEXT); lv_obj_set_pos(t, PG_X + 2, 12);
  top_clock = label(scr_main, "--:--", &lv_font_montserrat_20, C_TEXT); lv_obj_align(top_clock, LV_ALIGN_TOP_RIGHT, -12, 12);
  top_wifi = chip(scr_main);
  lv_obj_set_style_text_font(lv_obj_get_child(top_wifi, 0), &lv_font_montserrat_14, 0);
  lv_obj_set_style_pad_hor(top_wifi, 12, 0); lv_obj_set_style_pad_ver(top_wifi, 5, 0); lv_obj_set_style_radius(top_wifi, 14, 0);
  set_chip(top_wifi, LV_SYMBOL_WIFI "  Not connected", C_RED, C_RED_BG);

  // navigation rail: pill highlights the active tab
  const char *ic[4] = {LV_SYMBOL_HOME, LV_SYMBOL_LIST, LV_SYMBOL_WIFI, LV_SYMBOL_SETTINGS};
  const char *nm[4] = {"Home", "Apps", "Wi-Fi", "Setup"};
  for (int i = 0; i < 4; i++) {
    lv_obj_t *b = box(scr_main);
    lv_obj_set_size(b, 72, 62); lv_obj_set_pos(b, 4, 50 + i * 66);
    lv_obj_add_flag(b, LV_OBJ_FLAG_CLICKABLE);
    lv_obj_t *pill = box(b); lv_obj_set_size(pill, 52, 32); lv_obj_align(pill, LV_ALIGN_TOP_MID, 0, 4);
    lv_obj_set_style_radius(pill, 16, 0); lv_obj_set_style_bg_color(pill, C_LIME, 0); lv_obj_clear_flag(pill, LV_OBJ_FLAG_CLICKABLE);
    lv_obj_t *i1 = label(pill, ic[i], &lv_font_montserrat_20, C_DIM); lv_obj_center(i1);
    lv_obj_t *i2 = label(b, nm[i], &lv_font_montserrat_12, C_DIM); lv_obj_align(i2, LV_ALIGN_BOTTOM_MID, 0, -6);
    lv_obj_add_event_cb(b, nav_cb, LV_EVENT_CLICKED, (void *)(intptr_t)i);
    nav_btn[i] = b; nav_pill[i] = pill;
  }
  nav_badge = box(nav_btn[1]); lv_obj_set_size(nav_badge, 20, 20); lv_obj_align(nav_badge, LV_ALIGN_TOP_MID, 22, -2);
  lv_obj_set_style_radius(nav_badge, 10, 0); lv_obj_set_style_bg_opa(nav_badge, LV_OPA_COVER, 0);
  lv_obj_set_style_bg_color(nav_badge, C_TEXT, 0); lv_obj_set_style_border_width(nav_badge, 2, 0); lv_obj_set_style_border_color(nav_badge, C_BG, 0);
  lv_obj_t *bl = label(nav_badge, "0", &lv_font_montserrat_12, C_BG); lv_obj_center(bl);
  lv_obj_add_flag(nav_badge, LV_OBJ_FLAG_HIDDEN);

  for (int i = 0; i < 4; i++) page[i] = new_page();
  build_home(page[0]); build_apps(page[1]); build_wifi(page[2]); build_settings(page[3]);
  show_page(0);
}

static void place_top_wifi() { lv_obj_align_to(top_wifi, top_clock, LV_ALIGN_OUT_LEFT_MID, -12, 0); }

static void on_link_up() {
  if (!linked) { linked = true; lv_scr_load(scr_main); }
}
static void on_link_down() {
  linked = false;
  dlg_close(); kbd_close(); confirm_close(); busy_hide();
  pend_id = 0; last_scan = 0; if (scan_until) scan_done_ui();
  lv_scr_load(scr_wait);
}

static void handle_stat(JsonDocument &d) {
  char b[64];
  int cpu = (int)(d["cpu"].as<float>() + 0.5f);
  lv_arc_set_value(arc_cpu, cpu); lv_label_set_text_fmt(lbl_cpu, "%d%%", cpu);
  lv_obj_set_style_arc_color(arc_cpu, level_color(cpu), LV_PART_INDICATOR);
  uint64_t ru = d["ram_u"].as<uint64_t>(), rt = d["ram_t"].as<uint64_t>();
  int ram = rt ? (int)(100.0 * ru / rt + 0.5) : 0;
  lv_arc_set_value(arc_ram, ram); lv_label_set_text_fmt(lbl_ram, "%d%%", ram);
  lv_obj_set_style_arc_color(arc_ram, level_color(ram), LV_PART_INDICATOR);
  snprintf(b, sizeof b, "%.1f/%.0f GB", ru / 1073741824.0, rt / 1073741824.0); lv_label_set_text(sub_ram, b);
  float tc = d["temp"].as<float>();
  lv_arc_set_value(arc_tmp, (int)tc); snprintf(b, sizeof b, "%.0f" "\xC2\xB0" "C", tc); lv_label_set_text(lbl_tmp, b);
  lv_obj_set_style_arc_color(arc_tmp, tc >= 75 ? C_RED : tc >= 65 ? C_AMBER : C_LIME, LV_PART_INDICATOR);

  JsonArray disks = d["disks"].as<JsonArray>();
  for (int i = 0; i < 3; i++) {
    JsonObject k = (i < (int)disks.size()) ? disks[i].as<JsonObject>() : JsonObject();
    if (!k.isNull() && k["ok"].as<bool>()) {
      uint64_t du = k["u"].as<uint64_t>(), dt = k["t"].as<uint64_t>();
      int pm = dt ? (int)(1000.0 * du / dt) : 0;
      fmt_pair(b, sizeof b, du, dt);
      lv_label_set_text(disk_val[i], b); lv_bar_set_value(disk_bar[i], pm, LV_ANIM_OFF);
      lv_obj_set_style_bg_color(disk_bar[i], level_color(pm / 10), LV_PART_INDICATOR);
      lv_obj_set_style_text_color(disk_val[i], C_DIM, 0);
    } else {
      lv_label_set_text(disk_val[i], "not connected"); lv_bar_set_value(disk_bar[i], 0, LV_ANIM_OFF);
      lv_obj_set_style_text_color(disk_val[i], C_RED, 0);
    }
    lv_obj_align(disk_val[i], LV_ALIGN_TOP_RIGHT, 0, 21 + i * 32);
  }
  fmt_rate(b, sizeof b, d["rx"].as<uint64_t>()); lv_label_set_text(lbl_rx, b);
  fmt_rate(b, sizeof b, d["tx"].as<uint64_t>()); lv_label_set_text(lbl_tx, b);
  fmt_uptime(b, sizeof b, d["up"].as<uint32_t>()); lv_label_set_text(lbl_up, b);
  lv_label_set_text(top_clock, d["clock"] | "--:--");

  copy_str(cur_ssid, sizeof cur_ssid, d["ssid"] | "");
  cur_sig = d["rssi"] | 0;
  copy_str(pi_ip, sizeof pi_ip, d["ip"] | "");
  // top bar: status only, no network name
  if (cur_ssid[0]) set_chip(top_wifi, LV_SYMBOL_WIFI "  Connected", C_LIME, C_LIME_BG);
  else             set_chip(top_wifi, LV_SYMBOL_WIFI "  Not connected", C_RED, C_RED_BG);
  place_top_wifi();
  // Wi-Fi page header
  lv_label_set_text(wifi_cur, cur_ssid[0] ? cur_ssid : "Not connected");
  if (cur_ssid[0]) snprintf(b, sizeof b, "Signal %d%%    IP %s", cur_sig, pi_ip); else snprintf(b, sizeof b, "Pick a network below");
  lv_label_set_text(wifi_sub, b);
  lv_obj_set_style_bg_color(wifi_icon, cur_ssid[0] ? C_LIME_BG : C_RED_BG, 0);
  lv_obj_set_style_text_color(lv_obj_get_child(wifi_icon, 0), cur_ssid[0] ? C_LIME : C_RED, 0);
}

static void handle_ctrs(JsonDocument &d) {
  JsonArray l = d["list"].as<JsonArray>();
  n_ctr = 0;
  for (JsonObject c : l) {
    if (n_ctr >= MAX_CTR) break;
    Ctr &x = ctrs[n_ctr++];
    copy_str(x.name, sizeof x.name, c["name"] | "");
    copy_str(x.image, sizeof x.image, c["image"] | "");
    copy_str(x.state, sizeof x.state, c["state"] | "");
    copy_str(x.status, sizeof x.status, c["status"] | "");
    x.cpu = c["cpu"] | 0.0f; x.mu = c["mu"].as<uint64_t>(); x.ml = c["ml"].as<uint64_t>();
  }
  const char *err = d["err"] | "";
  lv_label_set_text(apps_empty, err[0] ? err : "No containers on the Pi yet.");
  apps_refresh();
  dlg_refresh();
}

static void handle_wifi(JsonDocument &d) {
  JsonArray l = d["list"].as<JsonArray>();
  n_net = 0;
  for (JsonObject o : l) {
    if (n_net >= MAX_NET) break;
    Net &n = nets[n_net++];
    copy_str(n.ssid, sizeof n.ssid, o["ssid"] | "");
    n.sig = o["sig"] | 0; copy_str(n.sec, sizeof n.sec, o["sec"] | ""); n.cur = o["cur"] | false;
  }
  scan_done_ui();
  lv_label_set_text(wifi_hint, "No networks found. Tap Scan to try again.");
  wifi_list_refresh();
}

static void handle_res(JsonDocument &d) {
  int id = d["id"] | 0;
  bool ok = d["ok"] | false;
  const char *msg = d["msg"] | (ok ? "Done" : "Failed");
  if (id == pend_id) {
    bool was_wifi = pend_wifi;
    pend_id = 0; pend_wifi = false;
    if (was_wifi) busy_hide();
    show_toast(msg, ok);
    if (dlg && !find_ctr(dlg_name) && ok) dlg_close(); else dlg_refresh();
    if (was_wifi && ok) scan_cb(NULL);
  } else if (!ok) {
    show_toast(msg, false);
    if (scan_until) scan_done_ui();
  }
}

static void handle_hello(JsonDocument &d) {
  copy_str(pi_host, sizeof pi_host, d["host"] | "");
  copy_str(pi_ip, sizeof pi_ip, d["ip"] | "");
  copy_str(pi_model, sizeof pi_model, d["model"] | "");
  copy_str(pi_os, sizeof pi_os, d["os"] | "");
  copy_str(pi_agent, sizeof pi_agent, d["agent"] | "");
  settings_refresh();
}

static void dump_screenshot() {
  // Answer to SHOT: the line "SHOT 320 480", then the framebuffer as it is (RGB565 little endian, portrait).
  Serial.setTxTimeoutMs(2000);
  Serial.printf("SHOT %d %d\n", NATIVE_W, NATIVE_H);
  const uint8_t *p = (const uint8_t *)fb;
  size_t n = NATIVE_W * NATIVE_H * 2;
  for (size_t o = 0; o < n; o += 4096) Serial.write(p + o, min((size_t)4096, n - o));
  Serial.flush();
  Serial.println();
  Serial.setTxTimeoutMs(0);
}

static void handle_line(char *line) {
  if (line[0] != '{') {
    if (!strcmp(line, "SHOT")) dump_screenshot();
    else if (!strncmp(line, "TAP ", 4)) {
      int x, y; if (sscanf(line + 4, "%d %d", &x, &y) == 2) { inj_x = x; inj_y = y; inj_until = millis() + 120; }
    }
    return;
  }
  JsonDocument d;
  if (deserializeJson(d, line)) return;
  const char *t = d["t"] | "";
  last_rx = millis();
  on_link_up();
  if (!strcmp(t, "stat")) handle_stat(d);
  else if (!strcmp(t, "ctrs")) handle_ctrs(d);
  else if (!strcmp(t, "wifi")) handle_wifi(d);
  else if (!strcmp(t, "res")) handle_res(d);
  else if (!strcmp(t, "hello")) handle_hello(d);
}

static char *rxbuf = nullptr;
static size_t rxlen = 0;
#define RXMAX 16384
static void poll_serial() {
  int budget = 8192;
  while (Serial.available() && budget-- > 0) {
    char c = (char)Serial.read();
    if (c == '\n' || c == '\r') {
      if (rxlen) { rxbuf[rxlen] = 0; handle_line(rxbuf); rxlen = 0; }
    } else if (rxlen < RXMAX - 1) rxbuf[rxlen++] = c;
    else rxlen = 0;  // line too long: throw away what came so far
  }
}

void setup() {
  Serial.setRxBufferSize(8192);
  Serial.begin(115200);
  Serial.setTxTimeoutMs(0);

  prefs.begin("ipnas", false);
  brightness = prefs.getInt("bri", 200);
  flip = prefs.getBool("flip", false);

  ledcSetup(BL_CH, 5000, 8); ledcAttachPin(PIN_BL, BL_CH);  // Arduino core 2.x API (3.x replaced it with ledcAttach)
  set_backlight(0);

  if (!gfx->begin()) { while (true) delay(1000); }
  fb = gfx->getFramebuffer();
  gfx->fillScreen(0x0000); gfx->flush();
  Wire.begin(TOUCH_SDA, TOUCH_SCL, 400000);

  rxbuf = (char *)ps_malloc(RXMAX);

  lv_init();
  static lv_disp_draw_buf_t draw_buf;
  size_t buf_px = SCR_W * 40;
  lv_color_t *buf1 = (lv_color_t *)heap_caps_malloc(buf_px * sizeof(lv_color_t), MALLOC_CAP_INTERNAL | MALLOC_CAP_8BIT);
  lv_disp_draw_buf_init(&draw_buf, buf1, NULL, buf_px);
  static lv_disp_drv_t disp_drv;
  lv_disp_drv_init(&disp_drv);
  disp_drv.hor_res = SCR_W; disp_drv.ver_res = SCR_H;
  disp_drv.flush_cb = disp_flush; disp_drv.draw_buf = &draw_buf;
  lv_disp_t *disp = lv_disp_drv_register(&disp_drv);
  static lv_indev_drv_t indev_drv;
  lv_indev_drv_init(&indev_drv);
  indev_drv.type = LV_INDEV_TYPE_POINTER; indev_drv.read_cb = touch_read;
  lv_indev_drv_register(&indev_drv);

  lv_theme_t *th = lv_theme_default_init(disp, C_LIME, C_DIM, true, &lv_font_montserrat_14);
  lv_disp_set_theme(disp, th);

  build_wait();
  build_main();
  lv_scr_load(scr_wait);
  lv_timer_handler();
  set_backlight(brightness);
}

void loop() {
  static uint32_t last_hi = 0;
  uint32_t now = millis();
  poll_serial();
  if (now - last_hi > 2000) { send_hi(); last_hi = now; }
  if (linked && (int32_t)(millis() - last_rx) > 6000) on_link_down();
  if (pend_id && (int32_t)(millis() - pend_until) > 0) {
    bool was_wifi = pend_wifi; pend_id = 0; pend_wifi = false;
    if (was_wifi) busy_hide();
    show_toast("No answer from the Pi", false); dlg_refresh();
  }
  if (scan_until && (int32_t)(millis() - scan_until) > 0) { scan_done_ui(); show_toast("Wi-Fi scan timed out", false); }
  lv_timer_handler();
  delay(5);
}
