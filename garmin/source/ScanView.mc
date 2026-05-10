import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

class ScanView extends WatchUi.View {

    private var _timer as Timer.Timer;
    private var _frame as Number = 0;

    function initialize() {
        View.initialize();
        _timer = new Timer.Timer();
    }

    function onShow() as Void {
        System.println("ScanView.onShow");
        _timer.start(method(:onTick), 500, true);
    }

    function onHide() as Void {
        _timer.stop();
    }

    function onTick() as Void {
        _frame++;

        // Initial scan: trigger once at ~1s so UI renders first.
        if (_frame == 2 && !BleManager.isScanning() && !BleManager.isConnected()) {
            try { BleManager.startScan(); } catch (e) {}
        }

        // Restart scan if the BLE peer dropped (peer reboot, RF loss, etc.)
        // The delegate sets `wantsRescan` from the disconnect callback; we
        // service it here so we don't call BLE APIs from inside a BLE callback.
        if (BleManager.wantsRescan()) {
            BleManager.clearWantsRescan();
            if (!BleManager.isScanning() && !BleManager.isConnected()) {
                try { BleManager.startScan(); } catch (e) {}
            }
        }

        if (!BleManager.hasApsPushed() && BleManager.isConnected() && BleManager.isScanCompleted()) {
            BleManager.setApsPushed(true);
            var v = new NetworkListView();
            WatchUi.pushView(v, new NetworkListDelegate(v), WatchUi.SLIDE_LEFT);
            return;
        }
        WatchUi.requestUpdate();
    }

    function onUpdate(dc as Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, 14, Graphics.FONT_SMALL, "Deauther", Graphics.TEXT_JUSTIFY_CENTER);

        if (!BleManager.isConnected()) {
            var dotCount = _frame % 4;
            var dots = "";
            for (var i = 0; i < dotCount; i++) { dots = dots + "."; }
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, h / 2 - 30, Graphics.FONT_SMALL, "Scanning" + dots, Graphics.TEXT_JUSTIFY_CENTER);
            dc.drawText(w / 2, h / 2 - 8, Graphics.FONT_TINY, "for deauther", Graphics.TEXT_JUSTIFY_CENTER);
            // Always show debug state so we can see scan/pair progress.
            dc.setColor(Graphics.COLOR_YELLOW, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, h / 2 + 20, Graphics.FONT_XTINY, truncate(BleManager.getState(), 22), Graphics.TEXT_JUSTIFY_CENTER);
        } else {
            // Connected — show debug state so we can diagnose where we're stuck.
            dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, 38, Graphics.FONT_TINY, "Connected", Graphics.TEXT_JUSTIFY_CENTER);

            var y = 60;
            dc.setColor(Graphics.COLOR_YELLOW, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, y, Graphics.FONT_XTINY, "S: " + truncate(BleManager.getState(), 22), Graphics.TEXT_JUSTIFY_CENTER); y += 18;

            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(w / 2, y, Graphics.FONT_XTINY, "TX: " + truncate(BleManager.getLastSent(), 22), Graphics.TEXT_JUSTIFY_CENTER); y += 18;

            dc.drawText(w / 2, y, Graphics.FONT_XTINY, "RX: " + BleManager.getBytesRx() + "B", Graphics.TEXT_JUSTIFY_CENTER); y += 18;
            dc.drawText(w / 2, y, Graphics.FONT_XTINY, truncate(BleManager.getLastLine(), 26), Graphics.TEXT_JUSTIFY_CENTER); y += 18;
            dc.drawText(w / 2, y, Graphics.FONT_XTINY, "APs: " + BleManager.getAps().size(), Graphics.TEXT_JUSTIFY_CENTER);
        }
    }

    function truncate(s as String, n as Number) as String {
        if (s.length() > n) { return s.substring(0, n); }
        return s;
    }
}

class ScanDelegate extends WatchUi.BehaviorDelegate {

    function initialize() {
        BehaviorDelegate.initialize();
    }

    function onBack() as Boolean {
        return false;  // system exits the app
    }
}
