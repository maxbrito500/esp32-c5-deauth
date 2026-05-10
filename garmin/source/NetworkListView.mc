import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.WatchUi;

// Left/right margin to keep content inside the round Fenix 7 bezel
function circleInset(yMid as Number, screenSize as Number) as Number {
    var r  = screenSize / 2;
    var dy = yMid - r;
    if (dy < 0) { dy = -dy; }
    if (dy >= r) { return r; }
    var s = Math.sqrt((r * r - dy * dy).toFloat()).toNumber();
    var inset = r - s + 6;
    if (inset < 6) { inset = 6; }
    return inset;
}

class NetworkListView extends WatchUi.View {

    private var _selectedIndex as Number = 0;
    private var _scrollOffset  as Number = 0;

    const ROW_HEIGHT    = 36;
    const HEADER_HEIGHT = 48;
    const HINT_HEIGHT   = 28;

    function initialize() {
        View.initialize();
    }

    function onUpdate(dc as Dc) as Void {
        var w    = dc.getWidth();
        var h    = dc.getHeight();
        var aps  = BleManager.getAps();

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        if (!BleManager.isConnected()) {
            dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, h / 2 - 10, Graphics.FONT_SMALL, "Disconnected", Graphics.TEXT_JUSTIFY_CENTER);
            return;
        }

        if (aps.size() == 0) {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, h / 2 - 14, Graphics.FONT_SMALL, "No networks", Graphics.TEXT_JUSTIFY_CENTER);
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, h / 2 + 14, Graphics.FONT_TINY, "MENU to scan", Graphics.TEXT_JUSTIFY_CENTER);
            return;
        }

        // Header
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, 18, Graphics.FONT_SMALL, "Networks (" + aps.size() + ")", Graphics.TEXT_JUSTIFY_CENTER);
        var lineInset = circleInset(HEADER_HEIGHT - 2, h);
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(lineInset, HEADER_HEIGHT - 2, w - lineInset, HEADER_HEIGHT - 2);

        // Bottom bar: attack status or hint
        var barY = h - HINT_HEIGHT;
        if (BleManager.isAttacking()) {
            var barInset = circleInset(barY + HINT_HEIGHT / 2, h);
            dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_RED);
            dc.fillRectangle(barInset, barY, w - barInset * 2, HINT_HEIGHT);
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, barY + 4, Graphics.FONT_TINY,
                "ATTACKING  " + BleManager.getAttackSecs() + "s", Graphics.TEXT_JUSTIFY_CENTER);
        } else {
            dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, barY + 4, Graphics.FONT_TINY, "SEL=deauth  MENU=scan", Graphics.TEXT_JUSTIFY_CENTER);
        }

        // List rows
        var usableH     = barY - HEADER_HEIGHT;
        var visibleRows = usableH / ROW_HEIGHT;

        if (_selectedIndex < _scrollOffset) {
            _scrollOffset = _selectedIndex;
        }
        if (_selectedIndex >= _scrollOffset + visibleRows) {
            _scrollOffset = _selectedIndex - visibleRows + 1;
        }

        for (var i = 0; i < visibleRows && (i + _scrollOffset) < aps.size(); i++) {
            var listIdx    = i + _scrollOffset;
            var ap         = aps[listIdx] as Dictionary;
            var y          = HEADER_HEIGHT + (i * ROW_HEIGHT);
            var isSelected = (listIdx == _selectedIndex);
            var rowMid     = y + ROW_HEIGHT / 2;
            var inset      = circleInset(rowMid, h);

            if (isSelected) {
                dc.setColor(0x003366, 0x003366);
                dc.fillRectangle(inset, y, w - inset * 2, ROW_HEIGHT);
            }

            drawApRow(dc, ap, y, w, inset);
        }

        // Scroll indicator
        if (aps.size() > visibleRows) {
            var barTop  = HEADER_HEIGHT;
            var barH    = usableH;
            var thumbH  = (barH * visibleRows) / aps.size();
            if (thumbH < 10) { thumbH = 10; }
            var thumbY  = barTop + (barH * _scrollOffset) / aps.size();
            var thumbMid = thumbY + thumbH / 2;
            var sInset  = circleInset(thumbMid, h);
            dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(w - sInset + 2, thumbY, 3, thumbH);
        }
    }

    function drawApRow(dc as Dc, ap as Dictionary, y as Number, w as Number, inset as Number) as Void {
        var ssid = ap["ssid"] as String;
        var band = ap["band"] as String;
        var rssi = ap["rssi"];

        // Truncate SSID to fit row width
        var availW   = w - inset * 2 - 48;
        var maxChars = availW / 8;
        if (maxChars < 5) { maxChars = 5; }
        if (ssid.length() > maxChars) {
            ssid = ssid.substring(0, maxChars - 2) + "..";
        }

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(inset + 4, y + 2, Graphics.FONT_TINY, ssid, Graphics.TEXT_JUSTIFY_LEFT);

        // Band badge
        var bandColor = band.equals("5GHz") ? 0x9933FF : 0x00AAAA;
        dc.setColor(bandColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w - inset - 4, y + 2, Graphics.FONT_XTINY,
            band.equals("5GHz") ? "5G" : "2.4", Graphics.TEXT_JUSTIFY_RIGHT);

        // RSSI
        if (rssi != null) {
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w - inset - 4, y + 18, Graphics.FONT_XTINY,
                rssi + "dBm", Graphics.TEXT_JUSTIFY_RIGHT);
        }
    }

    function selectNext() as Void {
        var aps = BleManager.getAps();
        if (_selectedIndex < aps.size() - 1) {
            _selectedIndex++;
            WatchUi.requestUpdate();
        }
    }

    function selectPrevious() as Void {
        if (_selectedIndex > 0) {
            _selectedIndex--;
            WatchUi.requestUpdate();
        }
    }

    function getSelectedIndex() as Number {
        return _selectedIndex;
    }
}

class NetworkListDelegate extends WatchUi.BehaviorDelegate {

    private var _view as NetworkListView;

    function initialize(view as NetworkListView) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    function onSelect() as Boolean {
        var aps = BleManager.getAps();
        var idx = _view.getSelectedIndex();
        if (idx < 0 || idx >= aps.size()) { return true; }
        var ap    = aps[idx] as Dictionary;
        var apIdx = ap["idx"] as Number;
        var ssid  = ap["ssid"] as String;
        BleManager.sendSel(apIdx);
        BleManager.sendStart();
        WatchUi.pushView(new AttackView(ssid), new AttackDelegate(), WatchUi.SLIDE_LEFT);
        return true;
    }

    function onNextPage() as Boolean {
        _view.selectNext();
        return true;
    }

    function onPreviousPage() as Boolean {
        _view.selectPrevious();
        return true;
    }

    function onMenu() as Boolean {
        BleManager.sendScan();
        return true;
    }

    function onBack() as Boolean {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        return true;
    }
}
