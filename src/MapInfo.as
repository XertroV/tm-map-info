string currentMapUid;
MapInfo_UI@ g_MapInfo = null;

nvg::Texture@ tmDojoLogo = null;
nvg::Texture@ tmIOLogo = null;
nvg::Texture@ tmxLogo = null;

void CheckForNewMap() {
    CTrackMania@ app = cast<CTrackMania>(GetApp());
    string mapUid;

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
        log_trace("Instantiated map info");
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
    string AuthorCountryFlag = "";
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
        AuthorCountryFlag = map.AuthorZoneIconUrl.SubStr(map.AuthorZoneIconUrl.Length - 7);
        StartInitializationCoros();
    }

    void Shutdown() {
        SHUTDOWN = true;
    }

    void StartInitializationCoros() {
        startnew(CoroutineFunc(this.GetMapInfoFromCoreAPI));
        startnew(CoroutineFunc(this.RefreshMapInfoFromMapMonitorAPI));
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

        // these two are the same (2023-02-01)
        AuthorAccountId = info.AuthorAccountId;
        AuthorWebServicesUserId = info.AuthorWebServicesUserId;
        // Some campaign maps are authored by https://trackmania.io/#/player/nadeo and info.AuthorDisplayName isn't set for these maps.
        if (info.AuthorDisplayName.Length > 0)
            AuthorDisplayName = info.AuthorDisplayName;

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
        log_trace('MapInfo_Data loaded map data');
        startnew(CoroutineFunc(this.LoadThumbnail));
    }

    MapThumbnailTexture@ Textures = null;

    nvg::Texture@ ThumbnailTexture {
        get { return Textures is null ? null : Textures.nvgTex; }
    }
    UI::Texture@ UI_ThumbnailTexture {
        get { return Textures is null ? null : Textures.uiTex; }
    }

    void LoadThumbnail() {
        @Textures = TextureCache::Get(ThumbnailUrl);
    }

    const string GetNbPlayersRange() {
        // 100-200k
        // 10-20k
        // 20-30k
        // subtract by 1 here so 100k -> 99,999 => log10(99999) = 4.99999 -> rounds to 4 -> 10**4 = 10k
        float nDigits = Math::Log10(NbPlayers - 1);
        int rangeDelta = 10 ** int(Math::Floor(nDigits));
        auto lower = NbPlayers - rangeDelta;
        bool isMil = lower >= 1000000;
        string k = isMil ? "m" : "k";
        int divBy = isMil ? 1000000 : 1000;
        return tostring(lower / divBy) + "-" + tostring(NbPlayers / divBy) + k;
    }

    Json::Value@ UpdateMapInfoFromMapMonitorAPI(bool isRefresh = false) {
        auto resp = MapMonitor::GetNbPlayersForMap(uid);
        NbPlayers = resp.Get('nb_players', 98765);
        WorstTime = resp.Get('last_highest_score', 0);

        UpdateNbPlayersString();
        WorstTimeStr = Time::Format(WorstTime);

        LoadedNbPlayers = true;
        log_trace('MapInfo_Data loaded nb players: ' + NbPlayersStr);
        return resp;
    }

    void UpdateNbPlayersString() {
        NbPlayersStr = NbPlayers > 10000 && NbPlayers % 1000 == 0 ? GetNbPlayersRange() : tostring(NbPlayers);
        log_debug('Set NbPlayersStr to: ' + NbPlayersStr);
    }

    void RefreshMapInfoFromMapMonitorAPI() {
        auto prevNbPlayers = NbPlayers;
        log_debug('refresh map info pre: ' + prevNbPlayers);
        auto resp = UpdateMapInfoFromMapMonitorAPI(true);
        auto newNbPlayers = NbPlayers;
        log_debug('refresh map info new: ' + newNbPlayers);
        while (!SHUTDOWN && isLoading) yield();
        if (SHUTDOWN) return;
        if (prevNbPlayers < LoadingNbPlayersFlag && newNbPlayers != prevNbPlayers) {
            NbPlayers = prevNbPlayers;
            UpdateNbPlayersString();
            // sexy count up logic
            auto countAnim = AnimMgr(false, 1750);
            yield();
            while (!countAnim.IsDone) {
                countAnim.Update(true);
                NbPlayers = uint(Math::Round(Math::Lerp(float(prevNbPlayers), float(newNbPlayers), countAnim.Progress)));
                UpdateNbPlayersString();
                yield();
            }
            log_debug('new != prev, and done');
        } else log_debug('new == prev, and done');

        // add a random time to let the server have some time to cache the next value
        float refreshInSeconds = resp.Get('refresh_in', 150.0) + Math::Rand(0.0, 15.0);
        log_trace('Refreshing nb players in: (s) ' + refreshInSeconds);
        sleep(int(refreshInSeconds * 1000.0));

        if (SHUTDOWN) return;
        if (GetApp().RootMap is null || currentMapUid != uid) return;

        startnew(CoroutineFunc(this.RefreshMapInfoFromMapMonitorAPI));
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
        TMX::OpenTmxTrack(TrackID);
    }

    void OnClickTmxAuthorButton() {
        TMX::OpenTmxAuthor(TMXAuthorID);
    }

    const string GetTMioURL() {
        return "https://trackmania.io/#/leaderboard/" + uid + "?utm_source=mapinfo-plugin";
    }

    void OnClickTMioButton() {
        OpenBrowserURL(GetTMioURL());
    }

    void OnClickTMioAuthorButton() {
        OpenBrowserURL("https://trackmania.io/#/player/" + AuthorWebServicesUserId + "?utm_source=mapinfo-plugin");
    }

    void OnClickTMDojoButton() {
        OpenBrowserURL("https://tmdojo.com/maps/" + uid + "?utm_source=mapinfo-plugin");
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
            log_debug('nbUiLayers: ' + nbUiLayers + '; lastNbUilayers' + lastNbUilayers);
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
        if (!IsUISequencePlayingOrFinish(cmap.UI.UISequence)) return true;
        // do we ever show mapinfo outside of Playing/Finish?
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
        log_debug('test populated');
        while (!IsUIPopulated()) yield();
        log_debug('test safe');
        if (!IsSafeToCheckUI()) {
            log_warn("unexpectedly failed UI safety check. probably in the editor or something.");
            return;
        }
        log_debug('is safe');
        // once we detect things have started to load, wait another second
        log_debug('sleep');
        for (uint i = 0; i < 10; i++) yield();
        log_debug('assert safe');
        yield();
        while (!IsSafeToCheckUI()) yield(); // throw("Should only happen if we exit the map super fast.");
        log_debug('find UI elements');
        while (IsSafeToCheckUI() && !FindUIElements()) {
            sleep(100);
        }
        log_debug('done checking ui. found: ' + lastRecordsLayerIndex);
        yield();
        log_debug('initial records element vis check');
        yield();
        isRecordsElementVisible = IsSafeToCheckUI();
        log_debug('records element vis check, can proceed: ' + tostring(isRecordsElementVisible));
        yield();
        isRecordsElementVisible = isRecordsElementVisible && IsRecordElementVisible();
        yield();
        log_debug('records visible: ' + tostring(isRecordsElementVisible));
        yield();

        while (!SHUTDOWN) {
            yield();
            if (GetApp().RootMap is null || GetApp().RootMap.EdChallengeId != uid) break;
            isRecordsElementVisible = IsSafeToCheckUI() && IsRecordElementVisible();
        }
        log_debug('exited');
    }

    float slideFrameProgress = 1.0;

    private bool openedExploreNod = false;
    private CGameManialinkControl@ slideFrame = null;
    private CGameManialinkFrame@ Race_Record_Frame = null;
    vec2 mainFrameAbsPos;
    float mainFrameAbsScale;
    private bool IsRecordElementVisible() {
        auto cmap = GetApp().Network.ClientManiaAppPlayground;
        if (cmap is null) return false;
        if (slideFrame is null || Race_Record_Frame is null) {
            if (lastRecordsLayerIndex >= cmap.UILayers.Length) return false;
            auto layer = cmap.UILayers[lastRecordsLayerIndex];
            if (layer is null) return false;
            auto frame = cast<CGameManialinkFrame>(layer.LocalPage.GetFirstChild("frame-records"));
            if (frame is null) return false;
            @Race_Record_Frame = cast<CGameManialinkFrame>(frame.Parent);
            if (Race_Record_Frame is null) return false;
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
        if (Race_Record_Frame !is null && !Race_Record_Frame.Visible) return false;
        if (slideFrame.Parent !is null && !slideFrame.Parent.Visible) return false;
        mainFrameAbsPos = Race_Record_Frame.AbsolutePosition_V3;
        mainFrameAbsScale = Race_Record_Frame.AbsoluteScale;
        // if the abs scale is too low (or negative) it causes problems. no legit case is like this so just set to 1
        if (mainFrameAbsScale <= 0.05) mainFrameAbsScale = 1.0;
        slideFrameProgress = (slideFrame.RelativePosition_V3.x + 61.0) / 61.0;
        return slideFrameProgress > 0.0;
    }

    private uint lastRecordsLayerIndex = 14;
    private bool FindUIElements() {
        auto app = cast<CTrackMania>(GetApp());
        auto cmap = app.Network.ClientManiaAppPlayground;
        if (cmap is null) throw('should never be null');
        auto nbLayers = cmap.UILayers.Length;
        log_debug('nb layers: ' + nbLayers);
        bool foundRecordsLayer = lastRecordsLayerIndex < nbLayers
            && IsUILayerRecordLayer(cmap.UILayers[lastRecordsLayerIndex]);
        log_debug('did not find records layer with init check');
        if (!foundRecordsLayer) {
            // don't check very early layers -- might sometimes crash the game?
            for (uint i = 3; i < nbLayers; i++) {
                log_debug('checking layer: ' + i);
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
        log_debug('checking layer');
        if (layer is null) return false;
        log_debug('checking layer ML length');
        // when ManialinkPage length is zero, accessing stuff might crash the game (specifically, ManialinkPageUtf8)
        if (layer.ManialinkPage.Length == 0) return false;
        log_debug('checking layer ML');
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

    bool LoadingFlagFailed = false;

    // Call this only during `Render()`! Loading textures from outside the render function can crash the game.
    void CheckLoadCountryFlag() {
        // load the flag texture if we're using it
        if (!LoadingFlagFailed && flagTexture is null && S_ShowAuthorFlags && AuthorCountryFlag.EndsWith(".dds")) {
            @flagTexture = nvg::LoadTexture("img/Flags/" + AuthorCountryFlag.Replace(".dds", ".png"));
            if (flagTexture is null || flagTexture.GetSize().x == 0 || flagTexture.GetSize().y == 0) { // failed to load
                @flagTexture = null;
                LoadingFlagFailed = true;
            }
        }
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
    vec4 bounds = vec4(-10, -1, -1, -1);
    float xPad = 20.;
    vec2 recordsTL;
    vec2 recordsFullSize;
    float widthSquish;

    vec4 UpdateBounds() {
        screen = vec2(Draw::GetWidth(), Draw::GetHeight());
        if (screen.x == 0 || screen.y == 0) screen = baseRes;
        vec2 midPoint = screen / 2.0;
        // if we are <16:9 res, then we get squished width
        float screenScale = screen.y / baseRes.y;
        widthSquish = Math::Min(1., screen.x / (baseRes.x * screenScale));

        recordsTL = (mainFrameAbsPos * vec2(widthSquish, -1)) / 180 * (screen.y) + midPoint;
        recordsFullSize = vec2(fullWidthProp * mainFrameAbsScale * screen.y, 200);

        vec2 tr = recordsTL + vec2(fullWidthProp * screen.y * mainFrameAbsScale, 0);
        bounds.x = tr.x;
        bounds.y = tr.y;
        bounds.z = 0;
        bounds.w = heightProp * screen.y * mainFrameAbsScale;
        return bounds;
    }

    nvg::Texture@ flagTexture;

    AnimMgr@ mainAnim = AnimMgr();
    AnimMgr@ hoverAnim = AnimMgr();

    void Draw() {
        CheckLoadCountryFlag();

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

        float fs = fontProp * screen.y * mainFrameAbsScale;
        xPad = xPaddingProp * screen.y; // * mainFrameAbsScale
        float gap = gapProp * screen.y * mainFrameAbsScale;

        // check max size assuming refresh-leadersboards exists
        float recordsWidth = fullWidthProp * screen.y * mainFrameAbsScale;
        float maxTextSize = recordsWidth - (rect.w + gap + xPad) * 2.0;
        // if this is happening something is not right
        if (maxTextSize <= 0) return;

        string mainLabel = Icons::Users + " " + NbPlayersStr;

        nvg::Reset();

        nvg::Scale(widthSquish, 1);

        nvg::FontFace(g_NvgFont);
        nvg::FontSize(fs);
        nvg::TextAlign(nvg::Align::Center | nvg::Align::Middle);

        auto textSize = nvg::TextBounds(mainLabel);
        if (textSize.x > maxTextSize) {
            // don't change the fs var here b/c it makes the text in the side pullout smaller
            nvg::FontSize(fs * maxTextSize / textSize.x);
            textSize = nvg::TextBounds(mainLabel);
            // just set the max size to what we expect to get things pixel perfect.
            textSize.x = maxTextSize;
        }

        float width = xPad * 2.0 + textSize.x * mainFrameAbsScale;
        rect.x -= width;
        rect.z = width;
        float textHOffset = rect.w * .55 - textSize.y / 2.0;

        // debug rectangles drawn around records arrow and refresh lederboards (if it were pixel perfect)
        // DrawDebugRect(rect.xyz.xy + vec2(width - recordsWidth, 0), vec2(rect.w, rect.w));
        // DrawDebugRect(rect.xyz.xy + vec2(width - recordsWidth + rect.w + gap, 0), vec2(rect.w, rect.w));
        // DrawDebugRect(recordsTL, recordsFullSize);

        // animate sliding away when record UI opens/closes
        // first, set up a scissor similar to the records UI
        nvg::Scissor(rect.x, rect.y, rect.z, rect.w);
        // now, offset everything depending on slider progress
        nvg::Translate(vec2((1.0 - mainAnim.Progress) * rect.z, 0));
        // that's all we need.

        nvg::BeginPath();
        DrawBgRect(rect.xyz.xy, vec2(rect.z, rect.w));

        nvg::FillColor(vec4(1.0, 1, 1, 1));
        nvg::Text(rect.xyz.xy + vec2(rect.z, rect.w) * vec2(.5, .55), mainLabel);

        nvg::ClosePath();

        // reset scissor so we can draw the hover
        nvg::ResetScissor();
        nvg::ResetTransform();

        vec2 hoverScale(widthSquish, 1);
        bool rawHover = IsWithin(g_MouseCoords, rect.xyz.xy * hoverScale, vec2(rect.z * widthSquish, rect.w) + vec2(gap, 0))
            || IsWithin(g_MouseCoords, rect.xyz.xy * hoverScale + vec2(rect.z * widthSquish + gap, 0), lastMapInfoSize);
            ;
        if (hoverAnim.Update(!closed && rawHover, slideFrameProgress)) {
            DrawHoveredInterface(rect, fs, textHOffset, gap);
        } else {
            lastMapInfoSize = vec2();
        }
    }

    void Draw_LoadingScreen() {
        if (!S_ShowLoadingScreenInfo) return;

        string[] lines;
        lines.InsertLast(g_MapInfo.Name);
        lines.InsertLast("by " + g_MapInfo.AuthorDisplayName);
        lines.InsertLast("");
        lines.InsertLast("Published: " + g_MapInfo.DateStr);
        if (TOTDStr.Length > 0)
            lines.InsertLast("TOTD: " + TOTDStr);
        lines.InsertLast("# Finishes: " + NbPlayersStr);
        lines.InsertLast("Worst Time: " + WorstTimeStr);
        lines.InsertLast("TMX: " + TrackIDStr);

        auto bls = Meta::GetPluginFromID("BetterLoadingScreen");
        bool drawOverBLS = bls !is null && bls.Enabled;

        vec2 screen = vec2(Draw::GetWidth(), Draw::GetHeight());
        float fs = drawOverBLS ? 40.0 : (fontProp * screen.y);
        float yTop = screen.y * S_LoadingScreenYOffsetPct / 100.0;
        float gap = fs / 4.0;
        // 0.069 = 100/1440
        float lineHeight = fs + gap;
        float height = gap + lines.Length * lineHeight;
        vec4 bgRect = vec4(0, yTop, screen.x, height);
        vec2 pos = vec2((Math::Max(0, screen.x / screen.y - 1.77777777) / 2. + 0.069) * screen.y, yTop + gap);

        // thumbnail cacls
        float thumbH = height - gap * 2.0;
        bool willDrawThumbnail = (!drawOverBLS && ThumbnailTexture !is null) || (drawOverBLS && UI_ThumbnailTexture !is null);
        vec2 imgSize = vec2(thumbH, thumbH);
        vec2 imgPos = vec2(screen.x - imgSize.x - (Math::Max(0, screen.x / screen.y - 1.77777777) / 2. + 0.069) * screen.y, yTop + gap);

        // need this for BLS branches
        UI::DrawList@ dl = UI::GetForegroundDrawList();

        // we only use imgui drawList if we have to (BLS installed), otherwise use nvg for performance
        if (drawOverBLS) {
            if (g_ImguiFont is null) { // can happen if BLS installed after MapInfo running
                startnew(LoadImGUIFont);
                return;
            }
            // have to use imgui to draw atop better loading screen
            dl.AddRectFilled(bgRect, BgColor);
        } else {
            nvg::BeginPath();
            DrawBgRect(bgRect.xyz.xy, vec2(bgRect.z, bgRect.w));
            // text stuff for later, might as well run it here so its not wasting resources when BLS is installed
            nvg::TextAlign(nvg::Align::Top | nvg::Align::Left);
            nvg::FillColor(vec4(1,1,1,1));
            nvg::FontFace(g_NvgFont);
            nvg::FontSize(fs);
        }

        for (uint i = 0; i < lines.Length; i++) {
            if (drawOverBLS) {
                dl.AddText(pos, vec4(1,1,1,1), lines[i], g_ImguiFont);
            } else {
                if (i == 0 && NvgName !is null) NvgName.Draw(pos, vec3(1, 1, 1), fs, 1.0);
                else nvg::Text(pos, lines[i]);
            }
            pos.y += lineHeight;
        }

        if (willDrawThumbnail) {
            if (drawOverBLS) {
                dl.AddImage(UI_ThumbnailTexture, imgPos, imgSize);
            } else {
                DrawTexture(imgPos, imgSize, ThumbnailTexture);
            }
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
        nvg::Scale(widthSquish, 1);

        bool drawTotd = TOTDStr.Length > 0;

        // ! should match the number of calls to DrawDataLabels
        int nbRows = 7;
        if (!drawTotd) nbRows--;

        nvg::BeginPath();

        vec2 tl = rect.xyz.xy + vec2(rect.z + gap, 0);
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

        pos = DrawDataLabels(pos.xyz.xy, col, yStep, col2X, fs, "Name", CleanName, NvgName, alpha);
        // pos = DrawDataLabels(pos.xyz.xy, col, yStep, col2X, fs, "Name", CleanName);
        vec2 authorBtnPos = pos.xyz.xy;
        pos = DrawDataLabels(pos.xyz.xy, col, yStep, col2X, fs, "Author", AuthorDisplayName, null, 1.0, TMioAuthorButton, tmIOLogo, flagTexture);
        authorBtnPos += vec2(col2X + pos.w + xPad, -fs * 0.05);
        // pos = DrawDataLabels(pos.xyz.xy, col, yStep, col2X, fs, "Author WSID", AuthorWebServicesUserId);
        // pos = DrawDataLabels(pos.xyz.xy, col, yStep, col2X, fs, "Author AcctID", AuthorAccountId);
        pos = DrawDataLabels(pos.xyz.xy, col, yStep, col2X, fs, "Published", DateStr, null, 1.0, TMioButton, tmIOLogo);
        if (drawTotd)
            pos = DrawDataLabels(pos.xyz.xy, col, yStep, col2X, fs, "TOTD", TOTDStr);
        pos = DrawDataLabels(pos.xyz.xy, col, yStep, col2X, fs, "# Finishes", NbPlayersStr + " (" + TodaysDate + ")");
        pos = DrawDataLabels(pos.xyz.xy, col, yStep, col2X, fs, "Worst Time", WorstTimeStr);

        vec2 tmxLinePos = pos.xyz.xy; // + vec2(col2X + nvg::TextBounds(TrackIDStr).x + xPad, -fs * 0.05); // - vec2(xPad, xPad / 2.0);
        const string tmxLineLabel = UploadedToTmDojo > 0 ? "TM{X,Dojo}" : "TMX";
        pos = DrawDataLabels(pos.xyz.xy, col, yStep, col2X, fs, tmxLineLabel, TrackIDStr, null, 1.0, TMXButton, tmxLogo);
        tmxLinePos += vec2(col2X + pos.w + xPad, -fs * 0.05);

        // tmdojo button is a square with xpad/2 padding around a square that's the same as the font size
        vec2 dojoBtnSize = vec2(xPad + fs, xPad + fs);
        float dojoBtnX = fullWidth - xPad - dojoBtnSize.x;
        vec2 halfPad = vec2(xPad, xPad) / 2.;
        vec2 btnLogoSize = vec2(fs, fs);
        float farRightBound = tl.x + fullWidth;
        float btnSpaceNeeded = fs + xPad*2.0;
        if (tmDojoLogo !is null && @TmDojoButton !is null && tmxLinePos.x + btnSpaceNeeded < farRightBound) {
            TmDojoButton.DrawButton(tmxLinePos, btnLogoSize, vec4(), halfPad, mainAnim.Progress, widthSquish);
            DrawTexture(tmxLinePos, btnLogoSize, tmDojoLogo, 1.0);
        }

        if (tmxLogo !is null && @TMXAuthorButton !is null && authorBtnPos.x + btnSpaceNeeded < farRightBound) {
            TMXAuthorButton.DrawButton(authorBtnPos, btnLogoSize, vec4(), halfPad, mainAnim.Progress, widthSquish);
            DrawTexture(authorBtnPos, btnLogoSize, tmxLogo);
            authorBtnPos.x += xPad + fs;
        }

        /* Thumbnail*/

        // we added this earlier for indent convenience, subtract now to make maths work
        pos.x -= xPad;

        if (ThumbnailTexture !is null) {
            vec2 size = vec2(thumbnailHeight, thumbnailHeight);
            vec2 _tl = pos.xyz.xy + vec2(fullWidth, 0) / 2.0 - vec2(size.x / 2.0, 0);
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

    vec4 BgColor = vec4(0, 0, 0, .85);
    void DrawBgRect(vec2 pos, vec2 size) {
        nvg::Rect(pos, size);
        nvg::FillColor(BgColor);
        nvg::Fill();
    }

    vec4 DrawDataLabels(vec2 pos, vec4 col, float yStep, float col2X, float fs, const string &in label, const string &in value, NvgText@ textObj = null, float alpha = 1.0, NvgButton@ button = null, nvg::Texture@ extraLogoForBtn = null, nvg::Texture@ authorFlagTexture = null) {
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
            if (authorFlagTexture !is null) {
                c2Size.x += xPad / 2.0 + (fs*1.42f);
            }
            button.DrawButton(c2Pos + shapeOffs, c2Size, vec4(1, 1, 1, 1), vec2(xPad, xPad) / 2.0, mainAnim.Progress, widthSquish);
            // ! text must be the next thing drawn as the hover color is set by .DrawButton
        }

        vec2 flagPos = c2Pos;
        if (authorFlagTexture !is null) {
            c2Pos.x += xPad / 2.0 + (fs*1.42f);
        }

        if (textObj is null) {
            nvg::Text(c2Pos, value);
        } else {
            textObj.Draw(c2Pos, vec3(1, 1, 1), fs, alpha);
        }

        if (authorFlagTexture !is null) DrawTexture(flagPos + shapeOffs, vec2(fs*1.42f, fs), authorFlagTexture);
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
        if (!S_ShowDebugUI) return;

        UI::SetNextWindowSize(800, 500, UI::Cond::FirstUseEver);
        if (UI::Begin("\\$8f0" + Icons::Map + "\\$z Map Info -- Debug", S_ShowDebugUI, UI::WindowFlags::None)) {
            if (UI::BeginTable("mapInfoDebug", 3, UI::TableFlags::SizingFixedFit)) {
                UI::TableSetupColumn("key", UI::TableColumnFlags::WidthFixed);
                UI::TableSetupColumn("value", UI::TableColumnFlags::WidthStretch);
                UI::TableSetupColumn("copy", UI::TableColumnFlags::WidthFixed);

                DebugTableRowStr("uid", uid);
                DebugTableRowStr("author", author);
                DebugTableRowStr("Name", Name);
                DebugTableRowStr("RawName", RawName);
                DebugTableRowStr("CleanName", CleanName);
                DebugTableRowStr("NvgName", NvgName.ToString());

                DebugTableRowStr("AuthorAccountId", AuthorAccountId);
                DebugTableRowStr("AuthorDisplayName", AuthorDisplayName);
                DebugTableRowStr("AuthorWebServicesUserId", AuthorWebServicesUserId);
                DebugTableRowStr("AuthorCountryFlag", AuthorCountryFlag);
                DebugTableRowStr("FileName", FileName);
                DebugTableRowStr("FileUrl", FileUrl);
                DebugTableRowStr("ThumbnailUrl", ThumbnailUrl);
                DebugTableRowUint("TimeStamp", TimeStamp);
                DebugTableRowUint("AuthorScore", AuthorScore);
                DebugTableRowUint("GoldScore", GoldScore);
                DebugTableRowUint("SilverScore", SilverScore);
                DebugTableRowUint("BronzeScore", BronzeScore);
                DebugTableRowStr("DateStr", DateStr);

                DebugTableRowInt("UploadedToNadeo", UploadedToNadeo);
                DebugTableRowButton("TMioButton", TMioButton);
                DebugTableRowButton("TMioAuthorButton", TMioAuthorButton);
                DebugTableRowStr("tm.io URL", GetTMioURL());

                DebugTableRowInt("UploadedToTMX", UploadedToTMX);
                DebugTableRowInt("TMXAuthorID", TMXAuthorID);
                DebugTableRowInt("TrackID", TrackID);
                DebugTableRowStr("TrackIDStr", TrackIDStr);

                DebugTableRowStr("TMX API URL", TMX::getMapByUidEndpoint.Replace('{id}', uid));
                DebugTableRowJsonValueHandle("TMX_Info", TMX_Info);
                DebugTableRowButton("TMXButton", TMXButton);
                DebugTableRowButton("TMXAuthorButton", TMXAuthorButton);

                DebugTableRowUint("NbPlayers", NbPlayers);
                DebugTableRowUint("WorstTime", WorstTime);
                DebugTableRowStr("NbPlayersStr", NbPlayersStr);
                DebugTableRowStr("WorstTimeStr", WorstTimeStr);

                DebugTableRowStr("TOTDDate", TOTDDate);
                DebugTableRowInt("TOTDDaysAgo", TOTDDaysAgo);
                DebugTableRowStr("TOTDStr", TOTDStr);

                DebugTableRowUint("LoadingStartedAt", LoadingStartedAt);
                DebugTableRowBool("LoadedMapData", LoadedMapData);
                DebugTableRowBool("LoadedNbPlayers", LoadedNbPlayers);
                DebugTableRowBool("LoadedWasTOTD", LoadedWasTOTD);

                DebugTableRowInt("UploadedToTmDojo", UploadedToTmDojo);
                DebugTableRowJsonValueHandle("TmDojoData", TmDojoData);
                DebugTableRowButton("TmDojoButton", TmDojoButton);
                DebugTableRowStr("TM Dojo API URL", TmDojo::mapInfoEndpoint.Replace('{uid}', uid));

                UI::EndTable();
            }
        }
        UI::End();
    }

    void DebugTableRowStr(const string &in key, const string &in value) {
        UI::PushID(key);

        UI::TableNextRow();
        UI::TableNextColumn();
        UI::Text(key);
        UI::TableNextColumn();
        UI::Text(value);
        UI::TableNextColumn();
        if (UI::Button(Icons::Clone)) IO::SetClipboard(value);

        UI::PopID();
    }
    void DebugTableRowInt(const string &in key, const int &in value) {
        DebugTableRowStr(key, tostring(value));
    }
    void DebugTableRowUint(const string &in key, const uint &in value) {
        DebugTableRowStr(key, tostring(value));
    }
    void DebugTableRowBool(const string &in key, bool value) {
        DebugTableRowStr(key, tostring(value));
    }
    void DebugTableRowButton(const string &in key, NvgButton@ btn) {
        DebugTableRowStr(key, btn is null ? "null" : Text::Format("%.3f", btn.anim.Progress));
    }
    void DebugTableRowJsonValueHandle(const string &in key, Json::Value@ value) {
        DebugTableRowStr(key, value is null ? "null" : Json::Write(value));
    }
}
