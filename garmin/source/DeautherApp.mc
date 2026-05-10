import Toybox.Application;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

class DeautherApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    function onStart(state as Dictionary?) as Void {
        System.println("DeautherApp.onStart");
        // Per the Garmin BLE samples: setupDelegate + registerProfile in
        // onStart, BEFORE getInitialView returns. Scanning is deferred to
        // the first UI tick so the simulator can render the UI before any
        // BLE state changes.
        BleManager.setupDelegate();
        BleManager.registerProfile();
    }

    function onStop(state as Dictionary?) as Void {
        try {
            BleManager.cleanup();
        } catch (e) {
        }
    }

    function getInitialView() as [Views] or [Views, InputDelegates] {
        System.println("DeautherApp.getInitialView");
        var v = new ScanView();
        return [v, new ScanDelegate()];
    }
}
