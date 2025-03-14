const string COTDQualiPPageName = "UIModule_COTDQualifications_QualificationsProgress";
const string COTDQualiPFrame = "COTDQualifications_QualificationsProgress";
const string COTDQualiRPageName = "UIModule_COTDQualifications_Ranking";
const string COTDQualiRFrame = "COTDQualifications_Ranking";
const string COTDQualiSlideFrame = "frame-hideable-content";
float COTDQualiFrameWidth = 60.0;
float COTDQualiFrameStartX = 0.0;
float COTDQualiFrameHeight = 63.0;
// button-hide

const string KOPageName = "UIModule_Knockout_KnockoutInfo";
const string KOFrame = "Knockout_KnockoutInfo";
const string KOSlideFrameId = "frame-content";
float KOFrameWidth = 53.5;
float KOFrameStartX = 1.0;
float KOFrameHeight = 77.666; // todo; can move up to overlap with previous thing to measure height

const string RecordPageName = "UIModule_Race_Record";
const string RecordFrame = "Race_Record";
const string RecordSlideFrameId = "frame-slide";
float RecordFrameWidth = 61.0;
float RecordFrameStartX = 0.0;
float RecordFrameHeight = 50; // todo

// button-hide, frame-content, COTDQualifications_QualificationsProgress

class ManialinkDetectorGroup {
    array<ManialinkDetector@> detectors;
    ManialinkDetectorGroup() {
    }
    ManialinkDetectorGroup@ Add(ManialinkDetector@ d) {
        detectors.InsertLast(d);
        return this;
    }
    ManialinkDetectorGroup@ Add(ManialinkDetector@ d, ManialinkDetector@ d2) {
        detectors.InsertLast(d);
        detectors.InsertLast(d2);
        return this;
    }

    bool get_isElementVisible() {
        for (uint i = 0; i < detectors.Length; i++) {
            if (detectors[i].isElementVisible) return detectors[i].isElementVisible;
        }
        return false;
    }

    float get_slideProgress() {
        for (uint i = 0; i < detectors.Length; i++) {
            if (detectors[i].isElementVisible) return detectors[i].slideProgress;
        }
        return 0.0;
    }

    float get_mainFrameAbsScale() {
        for (uint i = 0; i < detectors.Length; i++) {
            if (detectors[i].isElementVisible) return detectors[i].mainFrameAbsScale;
        }
        return 1.0;
    }

    float get_fullWidthPxOnBaseRes() {
        for (uint i = 0; i < detectors.Length; i++) {
            if (detectors[i].isElementVisible) return detectors[i].fullWidthPxOnBaseRes;
        }
        return 1.0;
    }

    vec2 get_mainFrameAbsPos() {
        for (uint i = 0; i < detectors.Length; i++) {
            if (detectors[i].isElementVisible) return detectors[i].mainFrameAbsPos;
        }
        return 1.0;
    }

    uint get_nbRecordsShown() {
        for (uint i = 0; i < detectors.Length; i++) {
            if (detectors[i].isElementVisible) return detectors[i].nbRecordsShown;
        }
        return 3;
    }

    // returns ML screen units
    float GuessHeight(MapInfo_Data@ mapInfo) {
        for (uint i = 0; i < detectors.Length; i++) {
            if (detectors[i].isElementVisible) return detectors[i].GuessHeight(mapInfo);
        }
        return 50.0;
    }

    void MonitorVisibility(MapInfo_Data@ mapInfo) {
        array<Meta::PluginCoroutine@> coros;
        for (uint i = 0; i < detectors.Length; i++) {
            coros.InsertLast(detectors[i].MonitorVisibilityCoro(mapInfo));
        }
        await(coros);
    }
}


class COTDQualiPMLDetector : ManialinkDetector {
    COTDQualiPMLDetector() {
        super(COTDQualiPPageName, COTDQualiPFrame, false);
        this.SetSlideFrame(COTDQualiSlideFrame, COTDQualiFrameWidth, COTDQualiFrameStartX);
        AbsPositionOffset = vec2(-27., 40.5);
        fullWidthPxOnBaseRes = 432.;
    }
    float GuessHeight(MapInfo_Data@ mapInfo) override {
        return COTDQualiFrameHeight;
    }
}

class COTDQualiRankingMLDetector : ManialinkDetector {
    COTDQualiRankingMLDetector() {
        super(COTDQualiRPageName, COTDQualiRFrame, false);
        this.SetSlideFrame(COTDQualiSlideFrame, COTDQualiFrameWidth, COTDQualiFrameStartX);
        AbsPositionOffset = vec2(-27., 40.5);
        fullWidthPxOnBaseRes = 432.;
    }
    float GuessHeight(MapInfo_Data@ mapInfo) override {
        return COTDQualiFrameHeight;
    }
}

class KnockoutMLDetector : ManialinkDetector {
    KnockoutMLDetector() {
        super(KOPageName, KOFrame, false);
        this.SetSlideFrame(KOSlideFrameId, KOFrameWidth, KOFrameStartX);
        AbsPositionOffset = vec2(0, 32.33);
        fullWidthPxOnBaseRes = 428.;
    }
    float GuessHeight(MapInfo_Data@ mapInfo) override {
        return KOFrameHeight;
    }
}

class RecordsMLDetector : ManialinkDetector {
    private CGameManialinkFrame@ frameRecords = null;
    private CGameManialinkFrame@ rankingsFrame = null;
    private CGameManialinkFrame@ hidePbFrame = null;
    private CGameManialinkFrame@ frameNoRecords = null;
    // uint nbRecordsShown;

    // todo, check child of MainFrame for visibility too (it is invisible here in ranked, etc)

    RecordsMLDetector() {
        super(RecordPageName, RecordFrame, false);
        fullWidthPxOnBaseRes = 400.;
        this.SetSlideFrame(RecordSlideFrameId, RecordFrameWidth, RecordFrameStartX);
    }

    void FindExtraAfterMainEl() override {
        @frameRecords = cast<CGameManialinkFrame>(MainFrame.GetFirstChild("frame-records"));
        @rankingsFrame = cast<CGameManialinkFrame>(MainFrame.GetFirstChild("frame-ranking"));
        @hidePbFrame = cast<CGameManialinkFrame>(MainFrame.GetFirstChild("frame-toggle-pb"));
        @frameNoRecords = cast<CGameManialinkFrame>(MainFrame.GetFirstChild("frame-no-records"));
        // auto backBtn = MainFrame.GetFirstChild("button-back-to-race");
    }

    bool ExtraAfterIsVisible() override {
        if (rankingsFrame !is null) {
            nbRecordsShown = 0;
            for (uint i = 0; i < rankingsFrame.Controls.Length; i++) {
                auto item = rankingsFrame.Controls[i];
                if (item.Visible) nbRecordsShown++;
            }
            if (hidePbFrame !is null && hidePbFrame.Visible) {
                nbRecordsShown++;
            }
            if (frameNoRecords !is null && frameNoRecords.Visible) {
                nbRecordsShown++;
            }
        }
        return (frameRecords !is null && frameRecords.Visible);
    }

    float GuessHeight(MapInfo_Data@ mapInfo) override {
        float recsShown = nbRecordsShown;
        if (mapInfo.UploadedToNadeo == 0) {
            recsShown = 3.0;
        }
        return (6. * (recsShown + 2));
    }
}

// name="UIModule_Knockout_KnockoutInfo"
//Knockout_KnockoutInfo
// frame-content
// from relative x 1.0 to -52.500
// - frame-toggle
// - frame-live-ranking


class ManialinkDetector {
    string frameid;
    string slideFrameId;
    bool hasSlideFrame = false;
    string pageName;
    uint pageix;
    uint nbRecordsShown;
    vec2 AbsPositionOffset;
    float fullWidthPxOnBaseRes = 400;

    ManialinkDetector(const string &in pageName, const string &in mainFrameId, bool runFind = false) {
        frameid = mainFrameId;
        this.pageName = pageName;
        this.slideFrameId = slideFrameId;
        hasSlideFrame = slideFrameId.Length > 0;
    }

    ~ManialinkDetector() {
        // if (MainFrame !is null) MainFrame.MwRelease();
        // if (SlideFrame !is null) SlideFrame.MwRelease();
        trace('releasing page');
        // if (MLPage !is null) MLPage.MwRelease();
        trace('released page');
    }

    ManialinkDetector@ RunFind() {
        FindMLElements(GetApp().Network.ClientManiaAppPlayground);
        return this;
    }

    ManialinkDetector@ SetSlideFrame(const string &in slideFrameId, float width, float showingX) {
        hasSlideFrame = true;
        this.slideFrameId = slideFrameId;
        slideShowingX = showingX;
        slideWidth = width;
        return this;
    }

    float GuessHeight(MapInfo_Data@ mapInfo) {
        // override this
        return 50.;
    }

    CGameManialinkFrame@ MainFrame;
    CGameManialinkFrame@ SlideFrame;
    // ~~assuming that ML elements are cleared when the page goes out of memory, keep a reference to it so we can MwRelease when we clean up.
    // CGameManialinkPage@ MLPage;

    bool FindMLElements(CGameManiaAppPlayground@ cmap) {
        if (cmap is null) return false;
        if (lastUILayerIndex >= cmap.UILayers.Length) return false;
        auto layer = cmap.UILayers[lastUILayerIndex];
        if (layer is null) return false;
        @MainFrame = cast<CGameManialinkFrame>(layer.LocalPage.GetFirstChild(frameid));
        if (MainFrame is null || MainFrame.Controls.Length == 0) return false;
        FindExtraAfterMainEl();
        if (hasSlideFrame) {
            @SlideFrame = cast<CGameManialinkFrame>(MainFrame.GetFirstChild(slideFrameId));
        }
        return true;
    }

    // for overriding
    void FindExtraAfterMainEl() {}
    bool ExtraAfterIsVisible() { return true; }

    vec2 mainFrameAbsPos;
    float mainFrameAbsScale = 1.0;
    float slideProgress = 1.0;
    float slideWidth = 1.0;
    float slideShowingX = 0.0;

    bool IsElementVisible() {
        auto cmap = GetApp().Network.ClientManiaAppPlayground;
        if (cmap is null) return false;
        if (MainFrame is null) {
            if (!FindMLElements(cmap)) return false;
            log_debug("\\$fa8FOUND ML ELEMENTS");
        }

        if (MainFrame is null || !MainFrame.Visible) return false;
        if (hasSlideFrame && (SlideFrame is null || !SlideFrame.Visible)) return false;

        if (!ParentsNullOrVisible(MainFrame, 7)) return false;
        mainFrameAbsPos = MainFrame.AbsolutePosition_V3 + AbsPositionOffset;
        // scale customized by some dedicated servers
        mainFrameAbsScale = MainFrame.AbsoluteScale;
        // if the abs scale is too low (or negative) it causes problems. no legit case is like this so just set to 1
        if (mainFrameAbsScale <= 0.1) mainFrameAbsScale = 1.0;
        if (hasSlideFrame) {
            slideProgress = (SlideFrame.RelativePosition_V3.x + slideWidth - slideShowingX) / slideWidth;
        }
        if (!ExtraAfterIsVisible()) return false;
        return (!hasSlideFrame || slideProgress > 0.0);
    }

    // bool IsUISafeToCheck(CGameManiaAppPlayground@ cmap = null) {
    //     if (cmap is null) @cmap = GetApp().Network.ClientManiaAppPlayground;
    //     return cmap !is null && cmap.UILayers.Length >= 3;
    // }

    bool IsSafeToCheckUI() {
        auto app = GetApp();
        if (app.RootMap is null || app.CurrentPlayground is null) return false;
        return IsUIPopulated();
    }

    Meta::PluginCoroutine@ MonitorVisibilityCoro(MapInfo_Data@ mi) {
        return startnew(CoroutineFuncUserdata(this.MonitorVisibility), mi);
    }

    bool isElementVisible = false;
    void MonitorVisibility(ref@ mapInfoR) {
        auto mapInfo = cast<MapInfo_Data>(mapInfoR);
        if (mapInfo is null) throw("Could not cast mapInfoR to mapinfo");

        while (!IsUIPopulated()) yield();
        // if (!IsSafeToCheckUI()) {

        if (!IsSafeToCheckUI()) {
            log_warn("unexpectedly failed UI safety check. probably in the editor or something.");
            return;
        }
        // wait a bit after things start to load

        for (uint i = 0; i < 10; i++) yield();
        while (!IsSafeToCheckUI()) yield(); // throw("Should only happen if we exit the map super fast.");

        while (!mapInfo.SHUTDOWN && IsSafeToCheckUI() && !FindUILayer()) {
            sleep(100);
        }
        if (mapInfo.SHUTDOWN) return;
        log_debug('done checking ui. found: ' + lastUILayerIndex);
        yield();
        log_debug('initial records element vis check');
        yield();
        isElementVisible = IsSafeToCheckUI();
        log_debug('records element vis check, can proceed: ' + tostring(isElementVisible));
        yield();
        isElementVisible = IsSafeToCheckUI() && IsElementVisible();
        yield();
        log_debug('records visible: ' + tostring(isElementVisible));
        yield();

        auto app = GetApp();
        while (!mapInfo.SHUTDOWN) {
            auto map = app.RootMap;
            if (map is null || map.EdChallengeId != mapInfo.uid) break;
            if (app.SystemOverlay.ScriptDebugger.Visibility != CGameScriptDebugger::EVisibility::Hidden) {
                @MainFrame = null;
                @SlideFrame = null;
                mapInfo.Shutdown();
                isElementVisible = false;
                break;
            }
            isElementVisible = IsSafeToCheckUI() && IsElementVisible();
            yield();
        }
        log_debug('exited');
    }

    private uint lastUILayerIndex = 12;
    protected bool FindUILayer() {
        auto app = cast<CTrackMania>(GetApp());
        auto cmap = app.Network.ClientManiaAppPlayground;
        if (cmap is null) throw('should never be null');
        auto nbLayers = cmap.UILayers.Length;
        log_debug('nb layers: ' + nbLayers);
        bool foundLayer = lastUILayerIndex < nbLayers
            && IsUILayerMatching(cmap.UILayers[lastUILayerIndex]);
        log_debug('did not find records layer with init check');
        if (!foundLayer) {
            // don't check very early layers -- might sometimes crash the game?
            for (uint i = 3; i < nbLayers; i++) {
                log_debug('checking layer: ' + i);
                if (IsUILayerMatching(cmap.UILayers[i])) {
                    lastUILayerIndex = i;
                    foundLayer = true;
                    break;
                }
            }
        }
        return foundLayer;
    }

    bool IsUILayerMatching(CGameUILayer@ layer) {
        log_debug('checking layer');
        if (layer is null) return false;
        log_debug('checking layer ML length');
        // when ManialinkPage length is zero, accessing stuff might crash the game (specifically, ManialinkPageUtf8)
        if (layer.ManialinkPage.Length == 0) return false;
        log_debug('checking layer ML');
        // accessing ManialinkPageUtf8 in some cases might crash the game
        if (layer.ManialinkPage.Length < 10) return false;
        return string(layer.ManialinkPage.SubStr(0, 127)).Trim().StartsWith('<manialink name="' + pageName);
    }


    uint lastNbUilayers;
    bool IsUIPopulated() {
        auto cmap = GetApp().Network.ClientManiaAppPlayground;
        auto cp = GetApp().CurrentPlayground;
        if (cmap is null || cp is null || cp.UIConfigs.Length == 0 || cmap.UI is null) return false;
        if (!IsGoodUISequence(cmap.UI.UISequence)) return false;
        auto nbUiLayers = cmap.UILayers.Length;
        // if the number of UI layers decreases it's probably due to a recovery restart, so we don't want to act on old references
        if (nbUiLayers <= 2 || nbUiLayers < lastNbUilayers) {
            log_debug('nbUiLayers: ' + nbUiLayers + '; lastNbUilayers' + lastNbUilayers);
            // lastNbUilayers = 0;
            if (nbUiLayers < lastNbUilayers - 5) {
                return false;
            }
        }
        lastNbUilayers = nbUiLayers;
        return true;
    }

}







bool IsGoodUISequence(CGamePlaygroundUIConfig::EUISequence uiSeq) {
    return uiSeq == CGamePlaygroundUIConfig::EUISequence::Playing
        || uiSeq == CGamePlaygroundUIConfig::EUISequence::Finish
        || uiSeq == CGamePlaygroundUIConfig::EUISequence::EndRound
        || uiSeq == CGamePlaygroundUIConfig::EUISequence::UIInteraction
        ;
}

bool IsUISequencePlayingOrFinish(CGamePlaygroundUIConfig::EUISequence uiSeq) {
    return uiSeq == CGamePlaygroundUIConfig::EUISequence::Playing
        || uiSeq == CGamePlaygroundUIConfig::EUISequence::Finish
        ;
}

bool ParentsNullOrVisible(CGameManialinkControl@ el, uint nbParentsToCheck = 1) {
    if (nbParentsToCheck == 0) return true;
    if (el is null || el.Parent is null) return true;
    if (!el.Parent.Visible) return false;
    return ParentsNullOrVisible(el.Parent, nbParentsToCheck - 1);
}
