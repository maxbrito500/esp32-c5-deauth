import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Timer;
import Toybox.WatchUi;

class AttackView extends WatchUi.View {

    private var _ssid  as String;
    private var _timer as Timer.Timer;

    function initialize(ssid as String) {
        View.initialize();
        _ssid  = ssid;
        _timer = new Timer.Timer();
    }

    function onShow() as Void {
        _timer.start(method(:onTick), 1000, true);
    }

    function onHide() as Void {
        _timer.stop();
    }

    function onTick() as Void {
        if (!BleManager.isAttacking()) {
            WatchUi.popView(WatchUi.SLIDE_RIGHT);
            return;
        }
        WatchUi.requestUpdate();
    }

    function onUpdate(dc as Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();

        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_BLACK);
        dc.clear();

        // Title
        dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, 32, Graphics.FONT_MEDIUM, "ATTACKING", Graphics.TEXT_JUSTIFY_CENTER);

        // Target SSID
        var ssid = _ssid;
        if (ssid.length() > 16) { ssid = ssid.substring(0, 14) + ".."; }
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h / 2 - 22, Graphics.FONT_SMALL, ssid, Graphics.TEXT_JUSTIFY_CENTER);

        // Elapsed time
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h / 2 + 10, Graphics.FONT_MEDIUM,
            BleManager.getAttackSecs() + "s", Graphics.TEXT_JUSTIFY_CENTER);

        // Hint
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(w / 2, h - 36, Graphics.FONT_TINY, "BACK to stop", Graphics.TEXT_JUSTIFY_CENTER);
    }
}

class AttackDelegate extends WatchUi.BehaviorDelegate {

    function initialize() {
        BehaviorDelegate.initialize();
    }

    function onBack() as Boolean {
        BleManager.sendStop();
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        return true;
    }
}
