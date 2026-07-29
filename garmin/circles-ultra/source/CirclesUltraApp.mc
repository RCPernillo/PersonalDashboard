import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

//! Circles Ultra - an Apple Watch Ultra style sphere face for Garmin.
class CirclesUltraApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    function onStart(state as Dictionary?) as Void {
        Config.load();
    }

    function onStop(state as Dictionary?) as Void {
    }

    function getInitialView() as [WatchUi.Views] or [WatchUi.Views, WatchUi.InputDelegates] {
        return [new CirclesUltraView()];
    }

    //! Fired when settings change on the phone or in the simulator.
    //! Re-reading here (and only here) is what keeps onUpdate free of
    //! Properties lookups.
    function onSettingsChanged() as Void {
        Config.load();
        WatchUi.requestUpdate();
    }
}
