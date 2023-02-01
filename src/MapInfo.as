string currentMapUid;
MapInfo_UI@ g_MapInfo = null;

nvg::Texture@ tmDojoLogo = null;
nvg::Texture@ tmIOLogo = null;
nvg::Texture@ tmxLogo = null;

void CheckForNewMap() {
    CTrackMania@ app = cast<CTrackMania>(GetApp());
    string mapUid;

    // bool rmNull = app.RootMap is null;
    // bool cmapPgMapNull = app.Network.ClientManiaAppPlayground is null
    //     || app.Network.ClientManiaAppPlayground.Playground is null
    //     || app.Network.ClientManiaAppPlayground.Playground.Map is null
    //     ;

    // todo: check app.RootMap.MapInfo.IsPlayable corresponds to unvalidated maps
    if (app.RootMap is null || !app.RootMap.MapInfo.IsPlayable || app.Editor !is null) { // app.CurrentPlayground is null ||
        mapUid = "";
    } else {
        mapUid = app.RootMap.MapInfo.MapUid;
    }

    if(mapUid != currentMapUid) {
        currentMapUid = mapUid;
        // startnew(OnNewMap);
        OnNewMap();
    }
}



void OnNewMap() {
    if (currentMapUid.Length == 0) {
        if (g_MapInfo !is null) g_MapInfo.Shutdown();
        @g_MapInfo = null;
        return;
    } else {
        if (g_MapInfo !is null) g_MapInfo.Shutdown();
        @g_MapInfo = MapInfo_UI();
        trace("Instantiated map info");
    }
    // CGameCtnChallenge@ map = GetApp().RootMap;
    // if (map is null) return;
}

bool isOnNadeoServices = false;
Json::Value@ nadeoData;

void getNadeoMapData(const string &in uid) {
    NadeoServices::AddAudience("NadeoLiveServices");
    while (!NadeoServices::IsAuthenticated("NadeoLiveServices")) yield();
    Net::HttpRequest@ req = NadeoServices::Get("NadeoLiveServices", NadeoServices::BaseURL()+"/api/token/map/"+uid);
    req.Start();
    while (!req.Finished()) yield();
    Json::Value resp = Json::Parse(req.String());
    isOnNadeoServices = (resp.GetType() == Json::Type::Object);
    @nadeoData = resp;
}


const uint LoadingNbPlayersFlag = 987654321;


/**
 * Class to manage getting map data from API sources. Intended as a base class for MapInfo_UI which handles drawing the info to the screen.
 */
class MapInfo_Data {
    string uid;
    string author;
    string Name;
    string RawName;
    string CleanName;
    NvgText@ NvgName;

    protected bool SHUTDOWN = false;

    string AuthorAccountId = "";
    string AuthorDisplayName = "";
    string AuthorWebServicesUserId = "";
    string FileName = "";
    string FileUrl = "";
    string ThumbnailUrl = "";
    uint TimeStamp = 0;
    uint AuthorScore = 0;
    uint GoldScore = 0;
    uint SilverScore = 0;
    uint BronzeScore = 0;
    string DateStr = "";

    // -1 for loading, 0 for no, 1 for yes
    int UploadedToNadeo = -1;
    NvgButton@ TMioButton = null;
    NvgButton@ TMioAuthorButton = null;

    int UploadedToTMX = -1;
    int TMXAuthorID = -1;
    int TrackID = -1;
    string TrackIDStr = "...";
    // When `null`, there's no TMX info. It should never be Json::Type::Null.
    Json::Value@ TMX_Info = null;
    NvgButton@ TMXButton = null;
    NvgButton@ TMXAuthorButton = null;

    uint NbPlayers = LoadingNbPlayersFlag;
    uint WorstTime = 0;
    string NbPlayersStr = "...";
    string WorstTimeStr = "";

    string TOTDDate = "";
    int TOTDDaysAgo = -1;
    string TOTDStr = "...";

    uint LoadingStartedAt = Time::Now;
    bool LoadedMapData = false;
    bool LoadedNbPlayers = false;
    bool LoadedWasTOTD = false;

    int UploadedToTmDojo = -1;
    Json::Value@ TmDojoData = null;
    NvgButton@ TmDojoButton = null;

    MapInfo_Data() {
        auto map = GetApp().RootMap;
        if (map is null) throw("Cannot instantiate MapInfo_Data when RootMap is null.");
        uid = map.EdChallengeId;
        SetName(map.MapName);
        author = map.AuthorNickName;

        AuthorDisplayName = map.MapInfo.AuthorNickName;

        StartInitializationCoros();
    }

    void Shutdown() {
        SHUTDOWN = true;
    }

    void StartInitializationCoros() {
        startnew(CoroutineFunc(this.GetMapInfoFromCoreAPI));
        startnew(CoroutineFunc(this.GetMapInfoFromMapMonitorAPI));
        startnew(CoroutineFunc(this.GetMapTOTDStatus));
        startnew(CoroutineFunc(this.GetMapTMXStatus));
        startnew(CoroutineFunc(this.GetMapTMDojoStatus));
        startnew(CoroutineFunc(this.MonitorRecordsVisibility));
    }

    bool OnMouseButton(bool down, int button) {
        return (TMXButton !is null && TMXButton.OnMouseClick(down, button))
            || (TMioButton !is null && TMioButton.OnMouseClick(down, button))
            || (TmDojoButton !is null && TmDojoButton.OnMouseClick(down, button))
            || (TMioAuthorButton !is null && TMioAuthorButton.OnMouseClick(down, button))
            || (TMXAuthorButton !is null && TMXAuthorButton.OnMouseClick(down, button))
            // || (Button2 !is null && Button.OnMouseClick(down, button))
            ;
    }

    void SetName(const string &in name) {
        RawName = name;
        Name = ColoredString(name);
        @NvgName = NvgText(name);
        CleanName = StripFormatCodes(name);
    }

    void GetMapInfoFromCoreAPI() {
        if (UploadedToNadeo == 1) return;
        // This should usually be near-instant b/c the game has probably already loaded this.
        auto info = Core::GetMapFromUid(uid);
        if (info is null) {
            UploadedToNadeo = 0;
            DateStr = "Never";
            return;
        }
        UploadedToNadeo = 1;
        @TMioButton = NvgButton(vec4(1, 1, 1, .8), vec4(0, 0, 0, 1), CoroutineFunc(OnClickTMioButton));
        @TMioAuthorButton = NvgButton(vec4(1, 1, 1, .8), vec4(0, 0, 0, 1), CoroutineFunc(OnClickTMioAuthorButton));

        AuthorAccountId = info.AuthorAccountId;
        AuthorDisplayName = info.AuthorDisplayName;
        AuthorWebServicesUserId = info.AuthorWebServicesUserId;

        SetName(info.Name);
        FileName = info.FileName;
        FileUrl = info.FileUrl;
        ThumbnailUrl = info.ThumbnailUrl;
        TimeStamp = info.TimeStamp;
        DateStr = FmtTimestamp(TimeStamp);

        AuthorScore = info.AuthorScore;
        GoldScore = info.GoldScore;
        SilverScore = info.SilverScore;
        BronzeScore = info.BronzeScore;

        LoadedMapData = true;
        trace('MapInfo_Data loaded map data');
        startnew(CoroutineFunc(this.LoadThumbnail));
    }

    nvg::Texture@ ThumbnailTexture = null;
    void LoadThumbnail() {
        auto req = Net::HttpGet(ThumbnailUrl);
        while (!req.Finished()) yield();
        if (req.ResponseCode() != 200) {
            warn('GET Thumbnail response: ' + req.ResponseCode());
            return;
        }
        @ThumbnailTexture = nvg::LoadTexture(req.Buffer());
    }

    const string GetNbPlayersRange() {
        // 100-200k
        // 10-20k
        // 20-30k
        // subtract by 1 here so 100k -> 99,999 => log10(99999) = 4.99999 -> rounds to 4 -> 10**4 = 10k
        float nDigits = Math::Log10(NbPlayers - 1);
        int rangeDelta = 10 ** int(Math::Floor(nDigits));
        auto lower = NbPlayers - rangeDelta;
        return tostring(lower / 1000) + "-" + tostring(NbPlayers / 1000) + "k";
    }

    void GetMapInfoFromMapMonitorAPI() {
        auto resp = MapMonitor::GetNbPlayersForMap(uid);
        NbPlayers = resp.Get('nb_players', 98765);
        WorstTime = resp.Get('last_highest_score', 0);

        NbPlayersStr = NbPlayers > 10000 && NbPlayers % 1000 == 0 ? GetNbPlayersRange() : tostring(NbPlayers);
        // NbPlayersStrShort = NbPlayers > 10000 ? tostring(NbPlayers / 1000) + "k" : NbPlayersStr;
        WorstTimeStr = Time::Format(WorstTime);

        LoadedNbPlayers = true;
        trace('MapInfo_Data loaded nb players: ' + NbPlayersStr);

        // add a random time to let the server have some time to cache the next value
        float refreshInSeconds = resp.Get('refresh_in', 150.0) + Math::Rand(0.0, 15.0);
        trace('Refreshing nb players in: (s) ' + refreshInSeconds);
        sleep(int(refreshInSeconds * 1000.0));
        if (SHUTDOWN) return;
        if (GetApp().RootMap is null || currentMapUid != uid) return;
        startnew(CoroutineFunc(this.GetMapInfoFromMapMonitorAPI));
        if (UploadedToNadeo == 0) { // check again in case of upload
            startnew(CoroutineFunc(this.GetMapInfoFromCoreAPI));
        }
    }

    void GetMapTOTDStatus() {
        TOTDDate = TOTD::GetDateMapWasTOTD_Async(uid);
        TOTDDaysAgo = TOTD::GetDaysAgo_Async(uid);
        if (TOTDDate.Length > 0 && TOTDDaysAgo >= 0) {
            TOTDStr = TOTDDate + " (" + (TOTDDaysAgo > 0 ? TOTDDaysAgo + " days ago)" : "today)");
        } else {
            TOTDStr = "";
        }
        LoadedWasTOTD = true;
    }

    void GetMapTMXStatus() {
        auto tmxTrack = TMX::GetMapFromUid(uid);
        if (tmxTrack !is null && tmxTrack.GetType() == Json::Type::Object) {
            UploadedToTMX = 1;
            TMXAuthorID = int(tmxTrack.Get('UserID', -1));
            TrackID = int(tmxTrack.Get('TrackID', -1));
            TrackIDStr = tostring(TrackID);
            @TMX_Info = tmxTrack;
            @TMXButton = NvgButton(vec4(1, 1, 1, .8), vec4(0, 0, 0, 1), CoroutineFunc(this.OnClickTmxButton));
            @TMXAuthorButton = NvgButton(vec4(1, 1, 1, .8), vec4(0, 0, 0, 1), CoroutineFunc(this.OnClickTmxAuthorButton));
        } else {
            UploadedToTMX = 0;
            TrackIDStr = "Not Uploaded";
        }
    }

    void GetMapTMDojoStatus() {
        auto tmDojoTrack = TmDojo::GetMapInfo(uid);
        if (tmDojoTrack !is null && tmDojoTrack.GetType() == Json::Type::Object && tmDojoTrack.HasKey("author")) {
            UploadedToTmDojo = 1;
            @TmDojoData = tmDojoTrack;
            @TmDojoButton = NvgButton(vec4(1, 1, 1, .8), vec4(0,0,0,1), CoroutineFunc(OnClickTMDojoButton));
        } else {
            UploadedToTmDojo = 0;
        }
    }

    void OnClickTmxButton() {
        OpenBrowserURL("https://trackmania.exchange/s/tr/" + TrackID);
    }

    void OnClickTmxAuthorButton() {
        OpenBrowserURL("https://trackmania.exchange/user/profile/" + TMXAuthorID);
    }

    void OnClickTMioButton() {
        OpenBrowserURL("https://trackmania.io/#/leaderboard/" + uid);
    }

    void OnClickTMioAuthorButton() {
        OpenBrowserURL("https://trackmania.io/#/player/" + AuthorWebServicesUserId);
    }

    void OnClickTMDojoButton() {
        OpenBrowserURL("https://tmdojo.com/maps/" + uid);
    }

    bool IsGoodUISequence(CGamePlaygroundUIConfig::EUISequence uiSeq) {
        return uiSeq == CGamePlaygroundUIConfig::EUISequence::Playing
            || uiSeq == CGamePlaygroundUIConfig::EUISequence::Finish
            || uiSeq == CGamePlaygroundUIConfig::EUISequence::EndRound
            ;
    }

    bool IsUISequencePlayingOrFinish(CGamePlaygroundUIConfig::EUISequence uiSeq) {
        return uiSeq == CGamePlaygroundUIConfig::EUISequence::Playing
            || uiSeq == CGamePlaygroundUIConfig::EUISequence::Finish
            ;
    }

    private uint lastNbUilayers = 0;
    bool IsUIPopulated() {
        auto cmap = GetApp().Network.ClientManiaAppPlayground;
        auto cp = GetApp().CurrentPlayground;
        if (cmap is null || cp is null || cp.UIConfigs.Length == 0 || cmap.UI is null) return false;
        if (!IsGoodUISequence(cmap.UI.UISequence)) return false;
        auto nbUiLayers = cmap.UILayers.Length;
        // if the number of UI layers decreases it's probably due to a recovery restart, so we don't want to act on old references
        if (nbUiLayers <= 2 || nbUiLayers < lastNbUilayers) {
            trace('nbUiLayers: ' + nbUiLayers + '; lastNbUilayers' + lastNbUilayers);
            return false;
        }
        lastNbUilayers = nbUiLayers;
        return true;
    }

    bool ScoreTableVisible() {
        // frame-scorestable-layer is the frame that shows scoreboard
        // but there's a ui layer with type ScoresTable that is called UIModule_Race_ScoresTable_Visibility
        // so probs best to check that (no string operations).
        auto cmap = GetApp().Network.ClientManiaAppPlayground;
        if (cmap is null) return false;
        for (uint i = 2; i < uint(Math::Min(8, cmap.UILayers.Length)); i++) {
            auto layer = cmap.UILayers[i];
            if (layer !is null && layer.Type == CGameUILayer::EUILayerType::ScoresTable) {
                return layer.LocalPage !is null && layer.LocalPage.MainFrame !is null && layer.LocalPage.MainFrame.Visible;
            }
        }
        return false;
    }

    bool SettingsOpen() {
        auto vp = GetApp().Viewport;
        if (vp.Overlays.Length < 3) return false;
        // 5 normally, report/key have 15 and 24; menu open has like 390
        // prior strat was satatic 10 but that doesn't work. (I had it at index 14 out of 17 total elements)
        // note: overlay has sort order 14, mb filter on that
        return vp.Overlays[vp.Overlays.Length - 3].m_CorpusVisibles.Length > 10;
    }

    // pretty expensive when layers are checked (1.3ms ish)
    // but caching the manialink controls seems fine
    CGameManialinkControl@ soloStartMenuFrame = null;
    CGameManialinkControl@ soloEndMenuFrame = null;
    bool SoloMenuOpen() {
        if (GetApp().PlaygroundScript is null) return false;
        auto cmap = GetApp().Network.ClientManiaAppPlayground;
        if (cmap is null || cmap.UILayers.Length < 2) return false;
        if (IsUISequencePlayingOrFinish(cmap.UI.UISequence)) return false;
        if (soloEndMenuFrame !is null && soloStartMenuFrame !is null) {
            return soloStartMenuFrame.Visible || soloEndMenuFrame.Visible;
        }
        bool foundStart = false, foundEnd = false;
        for (uint i = cmap.UILayers.Length - 1; i > 1; i--) {
            auto layer = cmap.UILayers[i];
            if (layer.ManialinkPage.Length < 10) continue;
            string mlpage = string(layer.ManialinkPage.SubStr(0, 64)).Trim();
            if (mlpage.StartsWith('<manialink name="UIModule_Campaign_EndRaceMenu"')) {
                foundEnd = true;
                try {
                    @soloEndMenuFrame = cast<CGameManialinkFrame>(layer.LocalPage.MainFrame.Controls[0]).Controls[0];
                    if (soloEndMenuFrame.Visible) return true;
                } catch {}
            }
            if (mlpage.StartsWith('<manialink name="UIModule_Campaign_StartRaceMenu"')) {
                foundStart = true;
                try {
                    @soloStartMenuFrame = cast<CGameManialinkFrame>(layer.LocalPage.MainFrame.Controls[0]).Controls[0];
                    if (soloStartMenuFrame.Visible) return true;
                } catch {}
            }
            if (foundEnd && foundStart) return false;
        }
        return false;
    }

    bool ShouldDrawUI {
        get {
            return _GameUIVisible && isRecordsElementVisible
                && !ScoreTableVisible() && !SettingsOpen()
                && !SoloMenuOpen()
                ;
        }
    }
    private bool isRecordsElementVisible = false;
    private void MonitorRecordsVisibility() {
        // these traces are to help investigate crashes -- can be commented later for production (or we could make a loglevel thing so ppl can turn them back on if they get crashes)
        trace('test populated');
        while (!IsUIPopulated()) yield();
        trace('test safe');
        if (!IsSafeToCheckUI()) {
            warn("unexpectedly failed UI safety check. probably in the editor or something.");
            return;
        }
        trace('is safe');
        // once we detect things have started to load, wait another second
        trace('sleep');
        for (uint i = 0; i < 10; i++) yield();
        trace('assert safe');
        yield();
        while (!IsSafeToCheckUI()) yield(); // throw("Should only happen if we exit the map super fast.");
        trace('find UI elements');
        while (IsSafeToCheckUI() && !FindUIElements()) {
            sleep(100);
        }
        trace('done checking ui. found: ' + lastRecordsLayerIndex);
        yield();
        trace('initial records element vis check');
        yield();
        isRecordsElementVisible = IsSafeToCheckUI();
        trace('records element vis check, can proceed: ' + tostring(isRecordsElementVisible));
        yield();
        isRecordsElementVisible = isRecordsElementVisible && IsRecordElementVisible();
        yield();
        trace('records visible: ' + tostring(isRecordsElementVisible));
        yield();

        while (!SHUTDOWN) {
            yield();
            if (GetApp().RootMap is null || GetApp().RootMap.EdChallengeId != uid) break;
            isRecordsElementVisible = IsSafeToCheckUI() && IsRecordElementVisible();
        }
        trace('exited');
    }

    float slideFrameProgress = 1.0;

    private bool openedExploreNod = false;
    private CGameManialinkControl@ slideFrame = null;
    private bool IsRecordElementVisible() {
        auto cmap = GetApp().Network.ClientManiaAppPlayground;
        if (cmap is null) return false;
        if (slideFrame is null) {
            if (lastRecordsLayerIndex >= cmap.UILayers.Length) return false;
            auto layer = cmap.UILayers[lastRecordsLayerIndex];
            if (layer is null) return false;
            auto frame = cast<CGameManialinkFrame>(layer.LocalPage.GetFirstChild("frame-records"));
            // should always be visible
            if (frame is null || !frame.Visible) return false;
            // if (!openedExploreNod) {
            //     openedExploreNod = true;
            //     ExploreNod(frame);
            // }
            if (frame.Controls.Length < 2) return false;
            @slideFrame = frame.Controls[1];
            if (slideFrame.ControlId != "frame-slide") throw("should be slide-frame");
        }
        if (!slideFrame.Parent.Visible) return false;
        slideFrameProgress = (slideFrame.RelativePosition_V3.x + 61.0) / 61.0;
        return slideFrameProgress > 0.0;
    }

    private uint lastRecordsLayerIndex = 14;
    private bool FindUIElements() {
        auto app = cast<CTrackMania>(GetApp());
        auto cmap = app.Network.ClientManiaAppPlayground;
        if (cmap is null) throw('should never be null');
        auto nbLayers = cmap.UILayers.Length;
        trace('nb layers: ' + nbLayers);
        bool foundRecordsLayer = lastRecordsLayerIndex < nbLayers
            && IsUILayerRecordLayer(cmap.UILayers[lastRecordsLayerIndex]);
        trace('did not find records layer with init check');
        if (!foundRecordsLayer) {
            // don't check very early layers -- might sometimes crash the game?
            for (uint i = 3; i < nbLayers; i++) {
                trace('checking layer: ' + i);
                if (IsUILayerRecordLayer(cmap.UILayers[i])) {
                    lastRecordsLayerIndex = i;
                    foundRecordsLayer = true;
                    break;
                }
            }
        }
        return foundRecordsLayer;
    }

    bool IsUILayerRecordLayer(CGameUILayer@ layer) {
        trace('checking layer');
        if (layer is null) return false;
        trace('checking layer ML length');
        // when ManialinkPage length is zero, accessing stuff might crash the game (specifically, ManialinkPageUtf8)
        if (layer.ManialinkPage.Length == 0) return false;
        trace('checking layer ML');
        // accessing ManialinkPageUtf8 in some cases might crash the game
        if (layer.ManialinkPage.Length < 10) return false;
        return string(layer.ManialinkPage.SubStr(0, 127)).Trim().StartsWith('<manialink name="UIModule_Race_Record"');
    }

    bool IsSafeToCheckUI() {
        auto app = GetApp();
        if (app.RootMap is null || app.CurrentPlayground is null || app.Editor !is null) return false;
        if (!IsUIPopulated()) return false;
        return true;
    }
}

/**
 * Class extension to draw map info to screen
 */
class MapInfo_UI : MapInfo_Data {
    MapInfo_UI() {
        super();
    }

    vec2 baseRes = vec2(2560.0, 1440.0);
    float heightProp = 64.0 / baseRes.y;
    float fullWidthProp = 400.0 / baseRes.y;
    float fontProp = 40.0 / baseRes.y;
    float xPaddingProp = 20.0 / baseRes.y;
    float gapProp = 8.0 / baseRes.y;
    float recordsHeight = 480.0 / baseRes.y;
    float fullRecordsHeight = 72.0 / baseRes.y + recordsHeight;

    // offset from middle of screen
    float topRightYOffs = (480.0 - baseRes.y / 2.0) / baseRes.y;
    float topRightXOffs = - (1720.0 - 840.0) / baseRes.x;
    vec2 trOffs = vec2(topRightXOffs, topRightYOffs);
    vec2 screen = baseRes;
    vec4 bounds = vec4(-10);
    float xPad = 20.;

    vec4 UpdateBounds() {
        screen = vec2(Draw::GetWidth(), Draw::GetHeight());
        vec2 midPoint = screen / 2.0;
        float screenScale = screen.y / baseRes.y;
        vec2 tr = midPoint + (trOffs * baseRes) * screenScale;
        bounds.x = tr.x;
        bounds.y = tr.y;
        bounds.z = 0;
        bounds.w = heightProp * screen.y;
        return bounds;
    }

    AnimMgr@ mainAnim = AnimMgr();
    AnimMgr@ hoverAnim = AnimMgr();

    void Draw() {
        if (!LoadedNbPlayers && Time::Now - LoadingStartedAt < 5000) return;
        auto cmap = GetApp().Network.ClientManiaAppPlayground;
        auto pgcsa = GetApp().Network.PlaygroundClientScriptAPI;
        auto ps = cast<CSmArenaRulesMode>(GetApp().PlaygroundScript);
        bool closed = !S_ShowMapInfo
            || !_GameUIVisible
            || !ShouldDrawUI
            || cmap is null || !IsGoodUISequence(cmap.UI.UISequence)
            || pgcsa is null || pgcsa.IsInGameMenuDisplayed
            || (ps !is null && ps.StartTime > 2147483000)
            ;
        if (closed) {
            lastMapInfoSize = vec2();
        }
        if (!mainAnim.Update(!closed, slideFrameProgress)) return;

        auto rect = UpdateBounds();

        float fs = fontProp * screen.y;
        xPad = xPaddingProp * screen.y;
        float gap = gapProp * screen.y;
        // check max size assuming refresh-leadersboards exists
        float recordsWidth = fullWidthProp * screen.y;
        float maxTextSize = recordsWidth - (rect.w + gap + xPad) * 2.0;
        string mainLabel = Icons::Users + " " + NbPlayersStr;

        nvg::Reset();

        nvg::FontFace(g_NvgFont);
        nvg::FontSize(fs);
        nvg::TextAlign(nvg::Align::Center | nvg::Align::Middle);

        auto textSize = nvg::TextBounds(mainLabel);
        if (textSize.x > maxTextSize) {
            fs *= maxTextSize / textSize.x;
            nvg::FontSize(fs);
            textSize = nvg::TextBounds(mainLabel);
        }

        // subtract 1 from width to avoid drawing 1 too many pixles when reducing the size b/c text is too large.
        float width = xPad * 2.0 + textSize.x - 1.;
        rect.x -= width;
        rect.z = width;
        float textHOffset = rect.w * .55 - textSize.y / 2.0;

        // DrawDebugRect(rect.xy + vec2(width - recordsWidth, 0), vec2(rect.w, rect.w));
        // DrawDebugRect(rect.xy + vec2(width - recordsWidth + rect.w + gap, 0), vec2(rect.w, rect.w));
        // DrawDebugRect(rect.xy + vec2(width - recordsWidth + (rect.w + gap) * 2.0, 0), vec2(rect.w, rect.w));
        // float IdealWidth = Math::Min(ScreenWidth, ScreenHeight * 16.0 / 9.0);
        // float AspectDiff = Math::Max(0.0, ScreenWidth / ScreenHeight - 16.0 / 9.0) / 2.0;
        // ButtonPosX = (0.028 * IdealWidth + ScreenHeight * AspectDiff) / ScreenWidth;
        // DrawDebugRect(vec2(ButtonPosX * ScreenWidth, rect.y), vec2(rect.w, rect.w));

        // animate sliding away when record UI opens/closes
        // first, set up a scissor similar to the records UI
        nvg::Scissor(rect.x, rect.y, rect.z, rect.w);
        // now, offset everything depending on slider progress
        nvg::Translate(vec2((1.0 - mainAnim.Progress) * rect.z, 0));
        // that's all we need.

        nvg::BeginPath();
        DrawBgRect(rect.xy, rect.zw);

        nvg::FillColor(vec4(1.0, 1, 1, 1));
        nvg::Text(rect.xy + rect.zw * vec2(.5, .55), mainLabel);

        nvg::ClosePath();

        // reset scissor so we can draw the hover
        nvg::ResetScissor();
        nvg::ResetTransform();

        bool rawHover = IsWithin(g_MouseCoords, rect.xy, rect.zw + vec2(gap, 0))
            || IsWithin(g_MouseCoords, rect.xy + vec2(rect.z + gap, 0), lastMapInfoSize);
            ;
        if (hoverAnim.Update(!closed && rawHover, slideFrameProgress)) {
            DrawHoveredInterface(rect, fs, textHOffset, gap);
        } else {
            lastMapInfoSize = vec2();
        }
    }

    void Draw_LoadingScreen() {
        // nvg test code at the begining to help test when this function was being called. can be removed
        // screen = vec2(Draw::GetWidth(), Draw::GetHeight());
        // nvg::Reset();
        // nvg::BeginPath();
        // nvg::Rect(screen / 4., screen / 2.);
        // nvg::FillColor(vec4(0, 0, 0, .5));
        // nvg::Fill();
        // nvg::ClosePath();

        if (!S_ShowLoadingScreenInfo) return;

        // have to use imgui to draw atop better loading screen
        UI::DrawList@ dl = UI::GetForegroundDrawList();

        string[] lines;

        // lines.InsertLast("Now loading...");
        // lines.InsertLast("");
        lines.InsertLast(g_MapInfo.Name);
        lines.InsertLast("by " + g_MapInfo.AuthorDisplayName);
        lines.InsertLast("");
        lines.InsertLast("Published: " + g_MapInfo.DateStr);
        if (TOTDStr.Length > 0)
            lines.InsertLast("TOTD: " + TOTDStr);
        lines.InsertLast("Nb Players: " + NbPlayersStr);
        lines.InsertLast("Worst Time: " + WorstTimeStr);
        lines.InsertLast("TMX: " + TrackIDStr);

        // cant find a reliable way to get text width with imgui.. so let's make it full-width
        dl.AddRectFilled(vec4(0, 80, Draw::GetWidth(), 50*lines.Length+20), vec4(0,0,0,0.75));
        for (uint i = 0; i < lines.Length; i++) {
            dl.AddText(vec2(100,100+(50*i)), vec4(1,1,1,1), lines[i], g_ImguiFont);
        }
    }

    float HoverInterfaceScale = 0.5357;
    float HI_MaxCol1 = 64.0;
    float HI_MaxCol2 = 64.0;
    vec2 lastMapInfoSize = vec2();

    void DrawHoveredInterface(vec4 rect, float fs, float textHOffset, float gap) {
        fs *= HoverInterfaceScale;
        xPad *= HoverInterfaceScale;
        textHOffset *= HoverInterfaceScale;

        float yStep = rect.w * HoverInterfaceScale;
        nvg::TextAlign(nvg::Align::Top | nvg::Align::Left);
        nvg::FontSize(fs);

        bool drawTotd = TOTDStr.Length > 0;

        // ! should match the number of calls to DrawDataLabels
        int nbRows = 7;
        if (!drawTotd) nbRows--;

        nvg::BeginPath();

        vec2 tl = rect.xy + vec2(rect.z + gap, 0);
        float rowsHeight = yStep * nbRows + xPad * 0.5;
        float fullWidth = HI_MaxCol1 + HI_MaxCol2 + xPad * 4.0;
        float thumbnailFrameHeight = Math::Min(fullRecordsHeight * screen.y - rowsHeight, fullWidth);
        float thumbnailHeight = thumbnailFrameHeight - xPad * 2.0;
        if (ThumbnailTexture is null) thumbnailFrameHeight = 0.0;
        vec2 fullSize = vec2(fullWidth, rowsHeight + thumbnailFrameHeight);

        // slider anim: scissor then offset
        nvg::Scissor(tl.x, tl.y, fullSize.x, fullSize.y);
        nvg::Translate(vec2(fullSize.x * (hoverAnim.Progress - 1.0), 0));
        lastMapInfoSize = fullSize * vec2(hoverAnim.Progress, 1);

        DrawBgRect(tl, fullSize);
        float col2X = HI_MaxCol1 + xPad * 2.0;

        HI_MaxCol1 = 0.0;
        HI_MaxCol2 = 0.0;

        float alpha = .9;
        vec4 col = vec4(1, 1, 1, alpha);

        // indent by xPad, add some y spacing. we use a vec4 here to get the return values for each column's width.
        vec4 pos = vec4(tl.x + xPad, tl.y + textHOffset + xPad * 0.5, 0, 0);

        // ! update nbRows if you add more DrawDataLabels

        pos = DrawDataLabels(pos.xy, col, yStep, col2X, fs, "Name", CleanName, NvgName, alpha);
        // pos = DrawDataLabels(pos.xy, col, yStep, col2X, fs, "Name", CleanName);
        vec2 authorBtnPos = pos.xy;
        pos = DrawDataLabels(pos.xy, col, yStep, col2X, fs, "Author", AuthorDisplayName, null, 1.0, TMioAuthorButton, tmIOLogo);
        authorBtnPos += vec2(col2X + pos.w + xPad, -fs * 0.05);
        // pos = DrawDataLabels(pos.xy, col, yStep, col2X, fs, "Author WSID", AuthorWebServicesUserId);
        // pos = DrawDataLabels(pos.xy, col, yStep, col2X, fs, "Author AcctID", AuthorAccountId);
        pos = DrawDataLabels(pos.xy, col, yStep, col2X, fs, "Published", DateStr, null, 1.0, TMioButton, tmIOLogo);
        if (drawTotd)
            pos = DrawDataLabels(pos.xy, col, yStep, col2X, fs, "TOTD", TOTDStr);
        pos = DrawDataLabels(pos.xy, col, yStep, col2X, fs, "# Finishes", NbPlayersStr + " (" + TodaysDate + ")");
        pos = DrawDataLabels(pos.xy, col, yStep, col2X, fs, "Worst Time", WorstTimeStr);

        vec2 tmxLinePos = pos.xy; // + vec2(col2X + nvg::TextBounds(TrackIDStr).x + xPad, -fs * 0.05); // - vec2(xPad, xPad / 2.0);
        const string tmxLineLabel = UploadedToTmDojo > 0 ? "TM{X,Dojo}" : "TMX";
        pos = DrawDataLabels(pos.xy, col, yStep, col2X, fs, tmxLineLabel, TrackIDStr, null, 1.0, TMXButton, tmxLogo);
        tmxLinePos += vec2(col2X + pos.w + xPad, -fs * 0.05);

        // tmdojo button is a square with xpad/2 padding around a square that's the same as the font size
        vec2 dojoBtnSize = vec2(xPad + fs, xPad + fs);
        float dojoBtnX = fullWidth - xPad - dojoBtnSize.x;
        vec2 halfPad = vec2(xPad, xPad) / 2.;
        vec2 btnLogoSize = vec2(fs, fs);
        float farRightBound = tl.x + fullWidth;
        float btnSpaceNeeded = fs + xPad*2.0;
        if (tmDojoLogo !is null && @TmDojoButton !is null && tmxLinePos.x + btnSpaceNeeded < farRightBound) {
            TmDojoButton.DrawButton(tmxLinePos, btnLogoSize, vec4(), halfPad, mainAnim.Progress);
            DrawTexture(tmxLinePos, btnLogoSize, tmDojoLogo, 1.0);
        }

        // if (tmIOLogo !is null && @TMioAuthorButton !is null && authorBtnPos.x + btnSpaceNeeded < farRightBound) {
        //     TMioAuthorButton.DrawButton(authorBtnPos, btnLogoSize, vec4(), halfPad, mainAnim.Progress);
        //     DrawTexture(authorBtnPos, btnLogoSize, tmIOLogo);
        //     authorBtnPos.x += xPad + fs;
        // }

        if (tmxLogo !is null && @TMXAuthorButton !is null && authorBtnPos.x + btnSpaceNeeded < farRightBound) {
            TMXAuthorButton.DrawButton(authorBtnPos, btnLogoSize, vec4(), halfPad, mainAnim.Progress);
            DrawTexture(authorBtnPos, btnLogoSize, tmxLogo);
            authorBtnPos.x += xPad + fs;
        }

        /** ! to add a button, you need to
         * increment pos by the relevant height (it's the next position drawn at).
         * If you don't use the same height as prior rows, add this height to the calculation of thumbnailFrameHeight. (you might need to add yStep otherwise).
         * use IsWithin to test button bounds for hover etc. probs good to make a button class that is a property of this class.
         * note: I've written an nvg button implementation here: https://github.com/XertroV/tm-editor-ui-toolbox/blob/master/src/NvgButton.as
         *       (also some related files). mb is useful.
         *       if you use that, i'd instantiate them in GetMapTMXStatus, and leave some handles as null otherwise.
         *       or do some overload trickery to put all that logic in the UI class, which is neater.
         * WRT buttons, my thoughts so far were to reduce the font size a bit and draw the button within the existing row heights.
         * (both for programming easy-ness and to keep the UI consistent)
         */

        // button impl here?

        /* Thumbnail*/

        // we added this earlier for indent convenience, subtract now to make maths work
        pos.x -= xPad;

        if (ThumbnailTexture !is null) {
            vec2 size = vec2(thumbnailHeight, thumbnailHeight);
            vec2 _tl = pos.xy + vec2(fullWidth, 0) / 2.0 - vec2(size.x / 2.0, 0);
            nvg::ClosePath();
            nvg::BeginPath();
            nvg::Rect(_tl, size);
            nvg::FillPaint(nvg::TexturePattern(_tl, size, 0.0, ThumbnailTexture, 1.0));
            nvg::Fill();
        }

        nvg::ClosePath();
        nvg::ResetTransform();
    }

    void DrawDebugRect(vec2 pos, vec2 size) {
        nvg::BeginPath();
        nvg::Rect(pos, size);
        nvg::StrokeColor(vec4(1, .5, 0, 1));
        nvg::Stroke();
        nvg::ClosePath();
    }

    void DrawBgRect(vec2 pos, vec2 size) {
        nvg::Rect(pos, size);
        nvg::FillColor(vec4(0, 0, 0, .85));
        nvg::Fill();
    }

    vec4 DrawDataLabels(vec2 pos, vec4 col, float yStep, float col2X, float fs, const string &in label, const string &in value, NvgText@ textObj = null, float alpha = 1.0, NvgButton@ button = null, nvg::Texture@ extraLogoForBtn = null) {
        auto labelTB = nvg::TextBounds(label);
        auto valueTB = nvg::TextBounds(value);
        nvg::FillColor(col);
        nvg::Text(pos, label);
        vec2 c2Pos = pos + vec2(col2X, 0);
        vec2 c2Size = valueTB;

        vec2 shapeOffs = vec2(0, c2Size.y * 0.05) * -1.0;

        bool drawLogo = false;
        if (button !is null) {
            if (extraLogoForBtn !is null) {
                c2Size.x += xPad / 2.0 + fs;
                drawLogo = true;
            }
            button.DrawButton(c2Pos + shapeOffs, c2Size, vec4(1, 1, 1, 1), vec2(xPad, xPad) / 2.0, mainAnim.Progress);
        }

        if (textObj is null) {
            nvg::Text(c2Pos, value);
        } else {
            textObj.Draw(c2Pos, vec3(1, 1, 1), fs, alpha);
        }
        if (drawLogo) {
            c2Pos.x += valueTB.x + xPad / 2.0;
            DrawTexture(c2Pos + shapeOffs, vec2(fs, fs), extraLogoForBtn);
        }
        pos.y += yStep;
        HI_MaxCol1 = Math::Max(labelTB.x, HI_MaxCol1);
        HI_MaxCol2 = Math::Max(c2Size.x, HI_MaxCol2);
        return vec4(pos.x, pos.y, labelTB.x, c2Size.x);
    }



    void Draw_DebugUI() {
        if (!S_ShowMapInfo) return;

        if (UI::Begin("\\$8f0" + Icons::Map + "\\$z Map Info " + uid, UI::WindowFlags::AlwaysAutoResize)) {

            // shitty debug view for now
            UI::BeginTable("mapInfoDebug", 2);

            DebugUITableRow("Name:", Name);
            DebugUITableRow("Author:", AuthorDisplayName);
            DebugUITableRow("Author WSID:", AuthorWebServicesUserId);
            DebugUITableRow("Author AcctID:", AuthorAccountId);
            DebugUITableRow("Published:", DateStr);
            DebugUITableRow("TOTD:", TOTDStr);
            DebugUITableRow("# Finishes:", NbPlayersStr);
            DebugUITableRow("Worst Time:", WorstTimeStr);

            UI::EndTable();
        }
        UI::End();
    }

    void DebugUITableRow(const string &in key, const string &in value) {
        UI::TableNextRow();
        UI::TableNextColumn();
        UI::Text(key);
        UI::TableNextColumn();
        UI::Text(value);
    }
}



// class MurderChairsUI {
//     MurderChairsState@ state;

//     void RenderUpdate(float dt) {
//         // for game events
//         vec2 pos = GameEventsTopLeft;
//         // draw maps along top
//         // draw game events
//         float yDelta = BaseFontHeight + EventLogSpacing;
//         for (int i = 0; i < int(state.activeEvents.Length); i++) {
//             if (state.activeEvents[i].RenderUpdate(dt, pos)) {
//                 state.activeEvents.RemoveAt(i);
//                 i--;
//             } else {
//                 pos.y += yDelta;
//             }
//         }
//     }
// }

// vec2 GameEventsTopLeft {
//     get {
//         float h = Draw::GetHeight();
//         float w = Draw::GetWidth();
//         float hOffset = 0;
//         float idealWidth = 1.7777777777777777 * h;
//         if (w < idealWidth) {
//             float newH = w / 1.7777777777777777;
//             hOffset = (h - newH) / 2.;
//             h = newH;
//         }
//         if (UI::IsOverlayShown()) hOffset += 24;
//         float wOffset = (float(Draw::GetWidth()) - (1.7777777777777777 * h)) / 2.;
//         vec2 tl = vec2(wOffset, hOffset) + vec2(h * 0.15, w * 0.025);
//         return tl;
//     }
// }


// class MCGameEvent {
//     vec4 col = vec4(1, 1, 1, 1);
//     string msg = "undefined";
//     float animDuration = 5.0;
//     float currTime = 0.0;
//     float t = 0.0;
//     float baseFontSize = BaseFontHeight;

//     bool RenderUpdate(float dt, vec2 pos) {
//         currTime += dt;
//         t = currTime / animDuration;
//         if (t > 1.) return true;
//         float alpha = Math::Clamp(5. - t * 5., 0., 1.);
//         float fs = baseFontSize * Math::Clamp((t + .2), 1, 1.2);
//         nvg::FontSize(fs);
//         nvg::FillColor(col * vec4(1, 1, 1, 0) + vec4(0, 0, 0, alpha));
//         nvg::Text(pos, msg);
//         return false;
//     }
// }
