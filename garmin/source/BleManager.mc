import Toybox.BluetoothLowEnergy;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

// Nordic UART Service UUIDs (string form)
const NUS_SERVICE = "6E400001-B5A3-F393-E0A9-E50E24DCCA9E";
const NUS_RX      = "6E400002-B5A3-F393-E0A9-E50E24DCCA9E";
const NUS_TX      = "6E400003-B5A3-F393-E0A9-E50E24DCCA9E";

class DeautherBleDelegate extends BluetoothLowEnergy.BleDelegate {

    function initialize() {
        BleDelegate.initialize();
    }

    function onScanResults(scanResults) as Void {
        BleManager.onScanResults(scanResults);
    }

    function onConnectedStateChanged(device, state) as Void {
        BleManager.onConnectedStateChanged(device, state);
    }

    function onCharacteristicChanged(characteristic, value) as Void {
        BleManager.onCharacteristicChanged(characteristic, value);
    }

    function onDescriptorWrite(descriptor, status) as Void {
        BleManager.onDescriptorWrite(descriptor, status);
    }

    function onProfileRegister(uuid, status) as Void {
        BleManager.onProfileRegister(uuid, status);
    }
}

module BleManager {

    var _initialized = false;
    var _profileRegistered = false;
    var _expectedApCount = -1;  // from "scan: N APs"
    var _scanCompleted = false;
    var _wantsRescan = false;   // set by disconnect callback; polled by ScanView
    var _lastSent = "";
    var _lastLine = "";
    var _state = "init";
    var _bytesRx = 0;
    var _delegate     = null;
    var _device       = null;
    var _rxChar       = null;
    var _svcUuid      = null;
    var _rxUuid       = null;
    var _txUuid       = null;
    var _cccdUuid     = null;
    var _connected    = false;
    var _scanning     = false;
    var _aps          = [];
    var _attacking    = false;
    var _attackSecs   = 0;
    var _attackAps    = 0;
    var _inApTable    = false;
    var _tmpAps       = [];
    var _lineBuf      = "";
    var _apsPushed    = false;

    function isInitialized() as Boolean { return _initialized; }
    function isConnected()   as Boolean { return _connected; }
    function isScanning()    as Boolean { return _scanning; }
    function isScanCompleted() as Boolean { return _scanCompleted; }
    function wantsRescan()    as Boolean { return _wantsRescan; }
    function clearWantsRescan() as Void { _wantsRescan = false; }
    function getLastSent() as String { return _lastSent; }
    function getLastLine() as String { return _lastLine; }
    function getState() as String { return _state; }
    function getBytesRx() as Number { return _bytesRx; }
    function isAttacking()   as Boolean { return _attacking; }
    function getAps()        as Array   { return _aps; }
    function getAttackSecs() as Number  { return _attackSecs; }
    function getAttackAps()  as Number  { return _attackAps; }
    function hasApsPushed()  as Boolean { return _apsPushed; }

    function setApsPushed(v as Boolean) as Void { _apsPushed = v; }

    function sendScan() as Void  { send("scan"); }
    function sendStart() as Void { send("start"); }
    function sendStop() as Void  { send("stop"); }
    function sendSel(idx as Number) as Void { send("sel " + idx); }

    // Setup the BLE delegate. Call this ONCE from AppBase.onStart, per the
    // pattern used by the Garmin SDK BLE samples.
    function setupDelegate() as Void {
        if (_initialized) { return; }
        _initialized = true;
        try {
            _svcUuid  = BluetoothLowEnergy.stringToUuid(NUS_SERVICE);
            _rxUuid   = BluetoothLowEnergy.stringToUuid(NUS_RX);
            _txUuid   = BluetoothLowEnergy.stringToUuid(NUS_TX);
            _cccdUuid = BluetoothLowEnergy.cccdUuid();
            _delegate = new DeautherBleDelegate();
            BluetoothLowEnergy.setDelegate(_delegate);

            // Drop any pairings left over from a prior app instance — they can
            // prevent fresh scan results from including the device on some
            // Garmin firmware revisions.
            try {
                var paired = BluetoothLowEnergy.getPairedDevices();
                if (paired != null) {
                    for (var d = paired.next(); d != null; d = paired.next()) {
                        try { BluetoothLowEnergy.unpairDevice(d as BluetoothLowEnergy.Device); } catch (e) {}
                    }
                }
            } catch (e) {}

            _state = "delegate set";
        } catch (e) {
            _state = "setup err: " + e.getErrorMessage();
        }
    }

    // Register the NUS profile with the BLE stack. Call this once after
    // setupDelegate (in AppBase.onStart).
    function registerProfile() as Void {
        if (_profileRegistered) { return; }
        try {
            BluetoothLowEnergy.registerProfile({
                :uuid => _svcUuid,
                :characteristics => [
                    { :uuid => _rxUuid },
                    { :uuid => _txUuid, :descriptors => [ _cccdUuid ] }
                ]
            });
            _profileRegistered = true;
            _state = "profile registered";
        } catch (e) {
            _state = "registerProfile err: " + e.getErrorMessage();
        }
    }

    // Begin BLE scanning. Triggered from the UI (or auto from ScanView).
    function startScan() as Void {
        _connected  = false;
        _scanning   = true;
        _aps        = [];
        _apsPushed  = false;
        _attacking  = false;
        _attackSecs = 0;
        _inApTable  = false;
        _lineBuf    = "";
        _scanCompleted = false;
        try {
            BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_SCANNING);
            _state = "scanning";
        } catch (e) {
            _scanning = false;
            _state = "startScan err: " + e.getErrorMessage();
        }
    }

    function cleanup() as Void {
        if (_scanning) {
            try { BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_OFF); } catch (e) {}
            _scanning = false;
        }
        if (_device != null) {
            try { BluetoothLowEnergy.unpairDevice(_device); } catch (e) {}
        }
    }

    function send(cmd as String) as Void {
        if (_rxChar == null) {
            _state = "send-no-rxChar";
            return;
        }
        var bytes = stringToBytes(cmd + "\n");
        try {
            (_rxChar as BluetoothLowEnergy.Characteristic).requestWrite(
                bytes,
                { :writeType => BluetoothLowEnergy.WRITE_TYPE_DEFAULT }
            );
            _lastSent = cmd;
            _state = "sent: " + cmd;
        } catch (e) {
            _state = "send err: " + e.getErrorMessage();
        }
    }

    // --- BLE event handlers ---

    function onProfileRegister(uuid, status) as Void {
        System.println("onProfileRegister status=" + status);
    }

    function onScanResults(scanResults) as Void {
        try {
            for (var sr = scanResults.next(); sr != null; sr = scanResults.next()) {
                var name = sr.getDeviceName();
                if (name == null) { continue; }
                var lower = name.toLower();
                if (lower.find("deauther") != null || lower.find("esp32c5") != null) {
                    _state = "found: " + name;
                    try {
                        BluetoothLowEnergy.setScanState(BluetoothLowEnergy.SCAN_STATE_OFF);
                    } catch (e) {}
                    _scanning = false;
                    BluetoothLowEnergy.pairDevice(sr);
                    return;
                }
            }
        } catch (e) {
            _state = "scan err: " + e.getErrorMessage();
        }
    }

    function onConnectedStateChanged(device, state) as Void {
        try {
            _state = "conn state=" + state;
            if (state == BluetoothLowEnergy.CONNECTION_STATE_CONNECTED) {
                _device    = device;
                _connected = true;

                var svc = device.getService(_svcUuid);
                if (svc == null) { _state = "svc null"; return; }

                var txChar = svc.getCharacteristic(_txUuid);
                if (txChar == null) { _state = "txChar null"; return; }

                _rxChar = svc.getCharacteristic(_rxUuid);
                if (_rxChar == null) { _state = "rxChar null"; return; }

                var cccd = txChar.getDescriptor(_cccdUuid);
                if (cccd == null) { _state = "cccd null"; return; }

                _state = "writing CCCD";
                cccd.requestWrite([0x01, 0x00]b);

            } else if (state == BluetoothLowEnergy.CONNECTION_STATE_DISCONNECTED) {
                _device     = null;
                _rxChar     = null;
                _connected  = false;
                _attacking  = false;
                _attackSecs = 0;
                _aps        = [];
                _apsPushed  = false;
                _scanCompleted = false;
                _inApTable  = false;
                _lineBuf    = "";
                _state = "disconnected";
                _wantsRescan = true;   // ScanView's timer will pick this up
            }
        } catch (e) {
            _state = "conn err: " + e.getErrorMessage();
        }
    }

    function onDescriptorWrite(descriptor, status) as Void {
        try {
            _state = "descWrite status=" + status;
            send("scan");
        } catch (e) {
            _state = "descWrite err: " + e.getErrorMessage();
        }
    }

    function onCharacteristicChanged(characteristic, value) as Void {
        try {
            _bytesRx = _bytesRx + value.size();
            _lineBuf = _lineBuf + bytesToString(value);

            var idx = _lineBuf.find("\n");
            while (idx != null) {
                var line = _lineBuf.substring(0, idx);
                _lineBuf = _lineBuf.substring(idx + 1, _lineBuf.length());
                if (line.length() > 0 && line.substring(line.length() - 1, line.length()).equals("\r")) {
                    line = line.substring(0, line.length() - 1);
                }
                if (line.length() > 0) {
                    _lastLine = line;
                }
                parseLine(line);
                idx = _lineBuf.find("\n");
            }
        } catch (e) {
            _state = "rx err: " + e.getErrorMessage();
        }
    }

    function parseLine(line as String) as Void {
        if (line.length() == 0) { return; }

        // Header: "idx  ch  band   rssi  bssid              ssid"
        if (line.find("idx") != null && line.find("ssid") != null && line.find("band") != null) {
            commitAps();
            _inApTable = true;
            _tmpAps    = [];
            return;
        }

        if (_inApTable) {
            var ap = parseApRow(line);
            if (ap != null) {
                _tmpAps.add(ap);
                // If we know the expected count, commit as soon as we hit it.
                if (_expectedApCount > 0 && _tmpAps.size() >= _expectedApCount) {
                    commitAps();
                }
                return;
            }
            // Non-AP line ends the table.
            commitAps();
        }

        // Scan complete: "scan: N APs" or "scan: no APs found"
        if (line.find("scan: ") != null && line.find("APs") != null) {
            // Extract count (-1 means none/unknown)
            var n = parseNumber(line, "scan: ", " ");
            _expectedApCount = (n > 0) ? n : 0;
            System.println("scan complete, expecting " + _expectedApCount + " APs");
            if (_expectedApCount == 0) {
                // No APs — commit empty list so the UI moves on.
                commitAps();
            } else {
                send("ls");
            }
            return;
        }

        if (line.find("attack: start") != null) {
            _attacking  = true;
            _attackSecs = 0;
            WatchUi.requestUpdate();
            return;
        }

        if (line.find("attack: stopped") != null || line.find("attack: not running") != null) {
            _attacking  = false;
            _attackSecs = 0;
            WatchUi.requestUpdate();
            return;
        }

        if (line.find("attack: ") != null && line.find("aps=") != null) {
            var secs = parseNumber(line, "attack: ", "s");
            if (secs >= 0) { _attackSecs = secs; }
            var aps = parseNumber(line, "aps=", null);
            if (aps >= 0) { _attackAps = aps; }
            WatchUi.requestUpdate();
            return;
        }
    }

    function commitAps() as Void {
        sortApsBySSID(_tmpAps);
        _aps       = _tmpAps;
        _tmpAps    = [];
        _inApTable = false;
        _scanCompleted = true;
        System.println("commitAps: " + _aps.size() + " networks");
        WatchUi.requestUpdate();
    }

    function parseApRow(line as String) {
        var tokens = splitTokens(line);
        if (tokens.size() < 5) { return null; }

        var idx = (tokens[0] as String).toNumber();
        if (idx == null) { return null; }

        var band = tokens[2] as String;
        if (!band.equals("2.4GHz") && !band.equals("5GHz")) { return null; }

        var ssid = "";
        for (var i = 5; i < tokens.size(); i++) {
            if (i > 5) { ssid = ssid + " "; }
            ssid = ssid + (tokens[i] as String);
        }

        return {
            "idx"  => idx,
            "ch"   => (tokens[1] as String).toNumber(),
            "band" => band,
            "rssi" => (tokens[3] as String).toNumber(),
            "bssid"=> tokens[4] as String,
            "ssid" => (ssid.length() == 0) ? "(hidden)" : ssid
        };
    }

    function parseNumber(line as String, prefix as String, terminator) as Number {
        var start = line.find(prefix);
        if (start == null) { return -1; }
        start = start + prefix.length();
        var numStr = "";
        for (var i = start; i < line.length(); i++) {
            var ch = line.substring(i, i + 1);
            if (terminator != null && ch.equals(terminator)) { break; }
            if (terminator == null && (ch.equals(" ") || ch.equals("\t"))) { break; }
            numStr = numStr + ch;
        }
        var n = numStr.toNumber();
        return (n != null) ? n : -1;
    }

    function sortApsBySSID(aps as Array) as Void {
        for (var i = 1; i < aps.size(); i++) {
            var key = aps[i] as Dictionary;
            var keySSID = (key["ssid"] as String).toLower();
            var j = i - 1;
            while (j >= 0 && compareStrings(((aps[j] as Dictionary)["ssid"] as String).toLower(), keySSID) > 0) {
                aps[j + 1] = aps[j];
                j--;
            }
            aps[j + 1] = key;
        }
    }

    function compareStrings(a as String, b as String) as Number {
        var aLen = a.length();
        var bLen = b.length();
        var minLen = (aLen < bLen) ? aLen : bLen;
        var aChars = a.toCharArray();
        var bChars = b.toCharArray();
        for (var i = 0; i < minLen; i++) {
            var ai = (aChars[i] as Number) & 0xFFFF;
            var bi = (bChars[i] as Number) & 0xFFFF;
            if (ai < bi) { return -1; }
            if (ai > bi) { return 1; }
        }
        if (aLen < bLen) { return -1; }
        if (aLen > bLen) { return 1; }
        return 0;
    }

    function splitTokens(line as String) as Array {
        var tokens = [];
        var len    = line.length();
        var start  = -1;
        for (var i = 0; i <= len; i++) {
            var isEnd   = (i == len);
            var isSpace = isEnd || line.substring(i, i + 1).equals(" ");
            if (!isSpace && start == -1) {
                start = i;
            } else if (isSpace && start != -1) {
                tokens.add(line.substring(start, i));
                start = -1;
            }
        }
        return tokens;
    }

    function bytesToString(bytes) as String {
        var s = "";
        for (var i = 0; i < bytes.size(); i++) {
            var b = bytes[i] & 0xFF;
            if ((b >= 32 && b < 128) || b == 10 || b == 13) {
                s = s + b.toChar().toString();
            }
        }
        return s;
    }

    function stringToBytes(s as String) {
        var chars = s.toCharArray();
        var bytes = new [chars.size()]b;
        for (var i = 0; i < chars.size(); i++) {
            bytes[i] = (chars[i] as Number) & 0xFF;
        }
        return bytes;
    }
}
