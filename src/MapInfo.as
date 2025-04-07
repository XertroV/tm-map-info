string currentMapUid;
MapInfo_UI@ g_MapInfo = null;

nvg::Texture@ tmDojoLogo = null;
nvg::Texture@ tmIOLogo = null;
nvg::Texture@ tmxLogo = null;

void CheckForNewMap() {
    CTrackMania@ app = cast<CTrackMania>(GetApp());
    string mapUid;

    // todo: check app.RootMap.MapInfo.IsPlayable corresponds to unvalidated maps
    // it does not, tmx 40066 is an example
    // || !app.RootMap.MapInfo.IsPlayable
    if (app.RootMap is null || app.Editor !is null) { // app.CurrentPlayground is null ||
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
    Net::HttpRequest@ req = NadeoServices::Get("NadeoLiveServices", NadeoServices::BaseURLLive()+"/api/token/map/"+uid);
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
class MapInfo_Data : MapInfo::Data {
    // Note: most properties defined in MapInfo::Data, which is a shared class, so that it can be exported.

    NvgText@ NvgName;

    bool SHUTDOWN = false;

    NvgButton@ TmDojoButton = null;

    NvgButton@ TMioButton = null;
    NvgButton@ TMioAuthorButton = null;

    NvgButton@ TMXButton = null;
    NvgButton@ TMXAuthorButton = null;

    bool isCotdQuali = false;
    bool isKoRounds = false;
    bool isNormalRecords = true;

    ManialinkDetectorGroup@ mlDetector = null;

    MapInfo_Data() {
        auto app = GetApp();
        auto map = app.RootMap;
        if (map is null) throw("Cannot instantiate MapInfo_Data when RootMap is null.");
        uid = map.EdChallengeId;
        SetName(map.MapName);
        MapComment = map.Comments;
        HasMapComment = MapComment.Length > 0;
        author = map.AuthorNickName;
        AuthorDisplayName = map.MapInfo.AuthorNickName;
        AuthorCountryFlag = map.AuthorZoneIconUrl.SubStr(map.AuthorZoneIconUrl.Length - 7);
        GetMapInfoFromMap();
        InitializeMLFinder();
        StartInitializationCoros();
        RefreshMedalColors();
    }

    void InitializeMLFinder() {
        auto si = cast<CTrackManiaNetworkServerInfo>(GetApp().Network.ServerInfo);
        isCotdQuali = si.CurGameModeStr == "TM_COTDQualifications_Online"
            || si.ClientUIRootModuleUrl.EndsWith("COTDQualifications.Script.txt");
        isKoRounds = si.CurGameModeStr.StartsWith("TM_Knockout");
        isNormalRecords = !isCotdQuali && !isKoRounds;
        if (isNormalRecords) @mlDetector = ManialinkDetectorGroup().Add(RecordsMLDetector());
        else if (S_EnableDuringCotdQuali && isCotdQuali) @mlDetector = ManialinkDetectorGroup().Add(COTDQualiPMLDetector(), COTDQualiRankingMLDetector());
        else if (S_EnableDuringKO && isKoRounds) @mlDetector = ManialinkDetectorGroup().Add(KnockoutMLDetector());
        // make sure we have something here since it is expected to be non-null
        if (mlDetector is null) {
            @mlDetector = ManialinkDetectorGroup().Add(RecordsMLDetector());
        }
        print("Initialize ML Finder, cotd: " + isCotdQuali + ", KO: " + isKoRounds + ", normal: " + isNormalRecords);
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
        startnew(CoroutineFunc(this.GetPersonalBest));
        startnew(CoroutineFunc(this.RefreshMedalColorsLoop));
    }

    void RefreshMedalColorsLoop() {
        while (!SHUTDOWN) {
            if (S_RefreshMedalColors) {
                S_RefreshMedalColors = false;
                RefreshMedalColors();
            }
            yield();
        }
    }

    void GetPersonalBest() {
        while (!SHUTDOWN) {
            auto app = GetApp();
            auto cmap = app.Network.ClientManiaAppPlayground;
            if (cmap is null) {
                warn("GetPersonalBest cmap null");
                return;
            }
            auto scoreMgr = cmap.ScoreMgr;
            auto userId = app.UserManagerScript.Users[0].Id;
            PersonalBestTime = scoreMgr.Map_GetRecord_v2(userId, uid, "PersonalBest", "", "TimeAttack", "");
            UpdatePBMedal();
            sleep(100);
        }
    }

    void UpdatePBMedal() {
        PersonalBestMedal = GetMedalForTime(PersonalBestTime);
    }

    int GetMedalForTime(uint time) {
        auto len = OrderedMedalTimesUint.Length;
        if (len > 0 && time <= OrderedMedalTimesUint[0]) return 0;
        if (len > 1 && time <= OrderedMedalTimesUint[1]) return 1;
        if (len > 2 && time <= OrderedMedalTimesUint[2]) return 2;
        if (len > 3 && time <= OrderedMedalTimesUint[3]) return 3;
        if (len > 4 && time <= OrderedMedalTimesUint[4]) return 4;
        if (len > 5 && time <= OrderedMedalTimesUint[5]) return 5;
        return 999;
    }

    void RefreshTOTDStatus() {
        startnew(CoroutineFunc(this.GetMapTOTDStatus));
    }

    bool OnMouseButton(bool down, int button) {
        return (TMXButton !is null && TMXButton.OnMouseClick(down, button))
            || (TMioButton !is null && TMioButton.OnMouseClick(down, button))
            || (TmDojoButton !is null && TmDojoButton.OnMouseClick(down, button))
            || (TMioAuthorButton !is null && TMioAuthorButton.OnMouseClick(down, button))
            || (TMXAuthorButton !is null && TMXAuthorButton.OnMouseClick(down, button))
            || (S_LakantaMode && S_DrawTMXBelowRecords && CheckClickNextTMX(down, button))
            // || (Button2 !is null && Button.OnMouseClick(down, button))
            ;
    }

    // will be overridden
    bool CheckClickNextTMX(bool down, int button) {
        return false;
    }

    void SetName(const string &in name) {
        RawName = name;
        Name = Text::OpenplanetFormatCodes(name);
        @NvgName = NvgText(name);
        CleanName = Text::StripFormatCodes(name);
    }

    void GetMapInfoFromCoreAPI() {
        if (UploadedToNadeo == 1) return;
        // This should usually be near-instant b/c the game has probably already loaded this.
        auto info = Core::GetMapFromUid(uid);
        if (info is null) {
            UploadedToNadeo = 0;
            DateStr = "Never";
            GetMapInfoFromMap();
            return;
        }
        UploadedToNadeo = 1;
        @TMioButton = NvgButton(vec4(1, 1, 1, .8), vec4(0, 0, 0, 1), CoroutineFunc(OnClickTMioButton));
        @TMioAuthorButton = NvgButton(vec4(1, 1, 1, .8), vec4(0, 0, 0, 1), CoroutineFunc(OnClickTMioAuthorButton));

        // these two are the same (2023-02-01)
        AuthorAccountId = info.AuthorAccountId;
        AuthorWebServicesUserId = info.AuthorWebServicesUserId;
        // Some campaign maps are authored by https://trackmania.io/#/player/nadeo and info.AuthorDisplayName isn't set for these maps.
        // if (info.AuthorDisplayName.Length > 0)
        //     AuthorDisplayName = info.AuthorDisplayName;
        // todo: check this works fine in most cases
        // see issue #20 for example of why this should be commented.

        if (AuthorDisplayName != "Nadeo")
            AuthorCurrentName = NadeoServices::GetDisplayNameAsync(AuthorAccountId);

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
        SetMedalTimeStrs();

        LoadedMapData = true;
        log_trace('MapInfo_Data loaded map data');
        startnew(CoroutineFunc(this.LoadThumbnail));
        startnew(CoroutineFunc(this.CheckChampionMedal));
        startnew(CoroutineFunc(this.CheckWarriorMedal));
    }

    void GetMapInfoFromMap() {
        auto map = GetApp().RootMap;
        if (map is null) return;
        auto mi = map.MapInfo;

        if (mi.AuthorNickName.Length > 0)
            AuthorDisplayName = mi.AuthorNickName;

        SetName(mi.Name);
        FileName = mi.FileName;
        FileUrl = mi.Path;

        AuthorScore = mi.TMObjective_AuthorTime;
        GoldScore = mi.TMObjective_GoldTime;
        SilverScore = mi.TMObjective_SilverTime;
        BronzeScore = mi.TMObjective_BronzeTime;
        SetMedalTimeStrs();
    }

    void SetMedalTimeStrs() {
        AuthorTimeStr = Time::Format(AuthorScore);
        GoldTimeStr = Time::Format(GoldScore);
        SilverTimeStr = Time::Format(SilverScore);
        BronzeTimeStr = Time::Format(BronzeScore);
        OrderedMedalTimes = {AuthorTimeStr, GoldTimeStr, SilverTimeStr, BronzeTimeStr};
        OrderedMedalTimesUint = {AuthorScore, GoldScore, SilverScore, BronzeScore};
    }

    void CheckChampionMedal() {
        if (S_IgnoreChampMedals) return;
#if DEPENDENCY_CHAMPIONMEDALS
        if (!Meta::GetPluginFromID("ChampionMedals").Enabled) return;
        auto startChampCheck = Time::Now;
        while (ChampionScore == 0 && Time::Now - startChampCheck < 30000 && !SHUTDOWN) {
            ChampionScore = ChampionMedals::GetCMTime();
            if (ChampionScore > 0) {
                ChampionTimeStr = Time::Format(ChampionScore);
                OrderedMedalTimesUint.InsertAt(0, ChampionScore);
                OrderedMedalTimes.InsertAt(0, ChampionTimeStr);
                OrderedMedalColors.InsertAt(0, S_MedalColorChampion);
                UpdatePBMedal();
                break;
            }
            sleep(250);
        }
#endif
    }

    void CheckWarriorMedal() {
        if (S_IgnoreWarriorMedals) return;
#if DEPENDENCY_WARRIORMEDALS
        if (!Meta::GetPluginFromID("WarriorMedals").Enabled) return;
        auto startWarriorCheck = Time::Now;
        while (WarriorScore == 0 && Time::Now - startWarriorCheck < 30000 && !SHUTDOWN) {
            WarriorScore = WarriorMedals::GetWMTime();
            if (WarriorScore > 0) {
                WarriorTimeStr = Time::Format(WarriorScore);
                uint index = ChampionScore > 0 && ChampionScore <= WarriorScore ? 1 : 0;
                OrderedMedalTimesUint.InsertAt(index, WarriorScore);
                OrderedMedalTimes.InsertAt(index, WarriorTimeStr);
                OrderedMedalColors.InsertAt(index, vec4(WarriorMedals::GetColorVec(), 1.0f));
                UpdatePBMedal();
                break;
            }
            sleep(250);
        }
#endif
    }

    void RefreshMedalColors() {
        OrderedMedalColors = {S_MedalColorAuthor, S_MedalColorGold, S_MedalColorSilver, S_MedalColorBronze};
#if DEPENDENCY_WARRIORMEDALS
        if (WarriorScore > 0) {
            OrderedMedalColors.InsertAt(0, vec4(WarriorMedals::GetColorVec(), 1.0f));
        }
#endif
        if (ChampionScore > 0) {
            OrderedMedalColors.InsertAt(0, S_MedalColorChampion);
        }
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
        // bug: 16000 shows as 6-16k
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
        log_debug('TMX track: ' + Json::Write(tmxTrack));
        if (tmxTrack !is null && tmxTrack.GetType() == Json::Type::Object) {
            // to add fields, see API/TMX.as `getMapByUidEndpoint`
            UploadedToTMX = 1;
            TrackID = int(tmxTrack.Get('MapId', -1));
            TrackIDStr = tostring(TrackID);
            TMXAwards = int(tmxTrack.Get('AwardCount', -1));
            TMXAwardsStr = tostring(TMXAwards);
            TMXAuthorID = -1;
            try {
                TMXAuthorID = int(tmxTrack['Authors'][0]['User']['UserId']);
            } catch {
                log_info('Failed to get TMXAuthorID = Authors[0].User.UserId');
            }

            string[]@ TMXMapTagIDs = GetTmxMapTagIds(tmxTrack);
            log_debug('TMXMapTagIDs: ' + Json::Write(TMXMapTagIDs.ToJson()));
            if(!TMXMapTagIDs.IsEmpty()) {
                string mapTag = string(TMX::mapTags[TMXMapTagIDs[0]]);
                TMXMapTags = mapTag;
                for(uint i = 1; i < TMXMapTagIDs.Length; i++) {
                    mapTag = string(TMX::mapTags[TMXMapTagIDs[i]]);
                    TMXMapTags += ", " + mapTag;
                }
            }

            @TMX_Info = tmxTrack;
            @TMXButton = NvgButton(vec4(1, 1, 1, .8), vec4(0, 0, 0, 1), CoroutineFunc(this.OnClickTmxButton));
            @TMXAuthorButton = NvgButton(vec4(1, 1, 1, .8), vec4(0, 0, 0, 1), CoroutineFunc(this.OnClickTmxAuthorButton));
            // for compatibility
            TMX_Info['TrackID'] = TrackID;
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

    // private uint lastNbUilayers = 0;
    // bool IsUIPopulated() {
    //     auto cmap = GetApp().Network.ClientManiaAppPlayground;
    //     auto cp = GetApp().CurrentPlayground;
    //     if (cmap is null || cp is null || cp.UIConfigs.Length == 0 || cmap.UI is null) return false;
    //     if (!IsGoodUISequence(cmap.UI.UISequence)) return false;
    //     auto nbUiLayers = cmap.UILayers.Length;
    //     // if the number of UI layers decreases it's probably due to a recovery restart, so we don't want to act on old references
    //     if (nbUiLayers <= 2 || nbUiLayers < lastNbUilayers) {
    //         log_debug('nbUiLayers: ' + nbUiLayers + '; lastNbUilayers' + lastNbUilayers);
    //         return false;
    //     }
    //     lastNbUilayers = nbUiLayers;
    //     return true;
    // }

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

    // pretty expensive when layers are checked (1.3ms ish)
    // but caching the manialink controls seems fine
    CGameManialinkControl@ soloStartMenuFrame = null;
    CGameManialinkControl@ soloEndMenuFrame = null;
    bool SoloMenuOpen() {
        if (GetApp().PlaygroundScript is null) return false;
        auto net = GetApp().Network;
        auto cmap = net.ClientManiaAppPlayground;
        if (cmap is null || cmap.UILayers.Length < 2) return false;
        if (!IsGoodUISequence(cmap.UI.UISequence)) return true;
        // do we ever show mapinfo outside of Playing/Finish?
        // if (backToRaceFromGhostVisible) return false;
        if (IsUISequencePlayingOrFinish(cmap.UI.UISequence)) return false;
        auto si = cast<CTrackManiaNetworkServerInfo>(net.ServerInfo);
        if (si.CurGameModeStr != "TM_Campaign_Local")
            return false;
        // this is very slow
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
                    if (soloEndMenuFrame.Visible) break;
                } catch {}
            }
            if (mlpage.StartsWith('<manialink name="UIModule_Campaign_StartRaceMenu"')) {
                foundStart = true;
                try {
                    @soloStartMenuFrame = cast<CGameManialinkFrame>(layer.LocalPage.MainFrame.Controls[0]).Controls[0];
                    if (soloStartMenuFrame.Visible) break;
                } catch {}
            }
            // if (foundEnd && foundStart) return false;
        }

        if (soloEndMenuFrame !is null && soloStartMenuFrame !is null) {
            return soloStartMenuFrame.Visible || soloEndMenuFrame.Visible;
        }

        return false;
    }

    bool ShouldDrawUI {
        get {
            return _GameUIVisible
                && (S_MinViewWhenRecordsCollapsed || mlDetector.isElementVisible)
                && (!isKoRounds || S_EnableDuringKO)
                && (!isCotdQuali || S_EnableDuringCotdQuali)
                && !ScoreTableVisible()
                && !SoloMenuOpen()
                ;
        }
    }
    // private bool isRecordsElementVisible = false;
    private void MonitorRecordsVisibility() {
        mlDetector.MonitorVisibility(this);
    }

    private bool openedExploreNod = false;
    uint nbRecordsShown = 0;

    bool ShouldDrawTMXAwards {
        get {
            return S_ShowTMXAwards && UploadedToTMX == 1 && TMXAwards >= 0;
        }
    }

    bool ShouldDrawTMXTags {
        get {
            return S_ShowTMXMapTags && UploadedToTMX == 1 && TMXMapTags.Length > 0;
        }
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
    // float fullWidthProp = 428.0 / baseRes.y;
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
    // vec2 recordsFullSize;
    float widthSquish;
    float recordsGuessedHeight;
    float extraHeightBelowRecords = 0;
    vec4 auxInfoRect;
    vec4 topAuxInfoRect;
    vec4 medalsInfoRect;

    vec4 UpdateBounds() {
        screen = vec2(Draw::GetWidth(), Draw::GetHeight());
        if (screen.x == 0 || screen.y == 0) screen = baseRes;
        vec2 midPoint = screen / 2.0;
        // if we are <16:9 res, then we get squished width
        float screenScale = screen.y / baseRes.y;
        widthSquish = Math::Min(1., screen.x / (baseRes.x * screenScale));
        auto mainFrameAbsPos = mlDetector.mainFrameAbsPos;
        auto mainFrameAbsScale = mlDetector.mainFrameAbsScale;

        recordsTL = (mainFrameAbsPos * vec2(widthSquish, -1)) / 180 * (screen.y) + midPoint;
        fullWidthProp = mlDetector.fullWidthPxOnBaseRes / baseRes.y;
        // recordsFullSize = vec2(fullWidthProp * mainFrameAbsScale * screen.y, 200);

        vec2 tr = recordsTL + vec2(fullWidthProp * screen.y * mainFrameAbsScale, 0);
        bounds.x = tr.x;
        bounds.y = tr.y;
        bounds.z = 0;
        bounds.w = heightProp * screen.y * mainFrameAbsScale;

        // an odd sized records window happens for a few reasons:
        // - less than 8 records (or player is last and 7 records)
        // - track not uploaded / other error (size: 50. 24.)
        // - no records / loading (size: 50. 6.)
        //
        // note: 64px / baseRes.y -> 8. in ML units

        // todo: check all error cases: frame-standard-required, frame-map-not-available, frame-missing-privilege

        auto mlScale = heightProp / 8.;
        recordsGuessedHeight = mlDetector.GuessHeight(this) * mlScale;
        nbRecordsShown = mlDetector.nbRecordsShown;
        // float recsShown = mlDetector.nbRecordsShown;
        // if (UploadedToNadeo == 0) {
        //     recsShown = 3.0;
        // }
        //(6. * (recsShown + 2)) * mlScale;

        return bounds;
    }

    nvg::Texture@ flagTexture;

    AnimMgr@ mainAnim = AnimMgr();
    AnimMgr@ hoverAnim = AnimMgr();

    // draw compact view stuff when true. bug: compact view on + loading map -> map info shows in middle of screen for a few seconds
    bool _minViewWhenRecordsCollapsed = false;
    // flag to control compact view after pause menu; only needed after
    bool _hasBeenOpenAfterMenu = false;

    void Draw() {
        CheckLoadCountryFlag();

        if (!LoadedNbPlayers && Time::Now - LoadingStartedAt < 5000) return;
        auto app = GetApp();
        auto cmap = app.Network.ClientManiaAppPlayground;
        auto pgcsa = app.Network.PlaygroundClientScriptAPI;
        // auto ps = cast<CSmArenaRulesMode>(GetApp().PlaygroundScript);
        bool closed = !S_ShowMapInfo
            || !_GameUIVisible;
        bool shouldDrawUI = !closed && ShouldDrawUI;
        shouldDrawUI = shouldDrawUI && !(
               cmap is null || !IsGoodUISequence(cmap.UI.UISequence)
            || pgcsa is null || pgcsa.IsInGameMenuDisplayed
            || int(app.LoadProgress.State) > 0 // Disabled=0, Displayed=1
        );
        closed = closed
            || !shouldDrawUI
            // || (ps !is null && ps.StartTime > 2147483000)
            ;

        // compact view stuff
        if (!shouldDrawUI && S_MinViewWhenRecordsCollapsed && _hasBeenOpenAfterMenu) {
            _hasBeenOpenAfterMenu = false;
            _minViewWhenRecordsCollapsed = false;
            // warn("setting has been open after menu = false");
        }
        // trace("shouldDrawUI: " + shouldDrawUI + ", closed: " + closed + ", minViewWhenRecordsCollapsed: " + _minViewWhenRecordsCollapsed + ", hasBeenOpenAfterMenu: " + _hasBeenOpenAfterMenu);

        // main closed/anim update
        if (closed) {
            lastMapInfoSize = vec2();
        }
        if (!mainAnim.Update(!closed, mlDetector.slideProgress) && !shouldDrawUI) {
            return;
        }

        // update flag to control compact view after pause menu
        if (!_hasBeenOpenAfterMenu && (mainAnim.IsDone || (!mlDetector.isElementVisible && S_MinViewWhenRecordsCollapsed))) {
            // warn("has been open after menu = true");
            _hasBeenOpenAfterMenu = true;
        }
        _minViewWhenRecordsCollapsed = S_MinViewWhenRecordsCollapsed && !closed && _hasBeenOpenAfterMenu;

        auto rect = UpdateBounds();

        float fs = fontProp * screen.y * mlDetector.mainFrameAbsScale;
        xPad = xPaddingProp * screen.y; // * mlDetector.mainFrameAbsScale
        float gap = gapProp * screen.y * mlDetector.mainFrameAbsScale;
        // guessed height of records
        float guessedHeightPx = recordsGuessedHeight * screen.y * mlDetector.mainFrameAbsScale;
        if (_minViewWhenRecordsCollapsed) {
            guessedHeightPx = guessedHeightPx * mainAnim.Progress;
        }

        // check max size assuming refresh-leadersboards exists
        float recordsWidth = fullWidthProp * screen.y * mlDetector.mainFrameAbsScale;
        float maxTextSize = recordsWidth - (rect.w + gap + xPad) * 2.0;
        // if this is happening something is not right
        if (maxTextSize <= 0) {
#if DEV
            warn("maxTextSize <= 0, recordsWidth: " + recordsWidth + ", rect.w: " + rect.w + ", gap: " + gap + ", xPad: " + xPad + ", fullWidthProp: " + fullWidthProp);
#endif
            return;
        }

        string mainLabel = Icons::Users + " " + NbPlayersStr;

        nvg::Reset();

        nvg::Scale(widthSquish, 1);

        nvg::FontFace(g_NvgFont);
        nvg::FontSize(fs);
        nvg::TextAlign(nvg::Align::Center | nvg::Align::Middle);

        auto textSize = nvg::TextBounds(mainLabel);
        if (textSize.x > maxTextSize) {
            // don't change the fs var here b/c it makes the text in the side pullout smaller
            nvg::FontSize(fs * maxTextSize / Math::Max(1.0, textSize.x));
            textSize = nvg::TextBounds(mainLabel);
            // just set the max size to what we expect to get things pixel perfect.
            textSize.x = maxTextSize;
        }

        float width = xPad * 2.0 + textSize.x * mlDetector.mainFrameAbsScale;
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

        // if we are not using Compact View
        if (!_minViewWhenRecordsCollapsed) {
            // now, offset everything depending on slider progress
            nvg::Translate(vec2((1.0 - mainAnim.Progress) * rect.z, 0));
            // that's all we need.
        } else {
            // don't translate left/right
        }

        nvg::BeginPath();
        DrawBgRect(rect.xyz.xy, vec2(rect.z, rect.w));

        nvg::FillColor(vec4(1.0, 1, 1, 1));
        nvg::Text(rect.xyz.xy + vec2(rect.z, rect.w) * vec2(.5, .55), mainLabel);

        nvg::ClosePath();

        // reset scissor so we can draw the hover
        nvg::ResetScissor();
        nvg::ResetTransform();

        // Aux info, name, author, medals, tmxid

        float hScale = 0.65;
        nvg::FontSize(fs * hScale);

        topAuxInfoRect = vec4();
        if (S_DrawTitleAuthorAboveRecords > 0) {
            int nbLines = S_DrawTitleAuthorAboveRecords == 3 ? 2 : 1;
            float topAuxHeight = rect.w * hScale * nbLines;
            topAuxInfoRect = vec4(rect.x + rect.z - recordsWidth, rect.y - gap * 1 - topAuxHeight, recordsWidth, topAuxHeight);
            Draw_MapNameAuthorAboveRecords(gap);
            // lets us refer to one value for extra height in hover side panel
            topAuxInfoRect.w += gap;
        }

        hScale = 0.75;
        nvg::FontSize(fs * hScale);

        extraHeightBelowRecords = 0;
        float tmpGap = gap * 2;
        if (_minViewWhenRecordsCollapsed) {
            tmpGap -= gap * (1.0 - mainAnim.Progress);
        }
        auxInfoRect = vec4(rect.x + rect.z - recordsWidth, rect.y + guessedHeightPx + tmpGap + rect.w, recordsWidth, rect.w * hScale);
        bool drawTmxId = S_DrawTMXBelowRecords && UploadedToTMX == 1;
        if (drawTmxId) {
            // todo: can't exactly remember what this was doing
            extraHeightBelowRecords += nbRecordsShown >= 8 ? (auxInfoRect.w * (nbRecordsShown - 8) + auxInfoRect.w + gap) : 0;
            Draw_TMXBelowRecords(auxInfoRect);
        }

        hScale = 0.6;
        nvg::FontSize(fs * hScale);
        float nbRows = (S_DrawOnly2MedalsBelowRecords ? 1. : 2.);
        bool drawPbs = S_ShowPbDeltaToMedals && PersonalBestTime > 0;
        float pbMult = drawPbs ? 2.0 : 1.0;
        nbRows *= pbMult;
        if (drawPbs && S_HideMedalsWorseThanPb) nbRows = Math::Min(float(PersonalBestMedal + 1), nbRows);
        nbRows = Math::Min(nbRows, S_MaxMedalRowsNb);
        float medalsHeight = nbRows * rect.w * hScale;

        medalsInfoRect = vec4(auxInfoRect.x, auxInfoRect.y, recordsWidth, medalsHeight);
        if (S_DrawMedalsBelowRecords || S_DrawOnly2MedalsBelowRecords) {
            if (drawTmxId) {
                medalsInfoRect.y += gap + auxInfoRect.w;
            }
            extraHeightBelowRecords += medalsHeight + gap;
            Draw_MedalsBelowRecords();
        }

        vec2 hoverScale(widthSquish, 1);
        /* 1st: detection of main rect
           2nd: detection of hovering side panel
           3rd: detection of hovering title/name above records
           */
        bool rawHover = IsWithin(g_MouseCoords, rect.xy * hoverScale, vec2(rect.z * widthSquish, rect.w) + vec2(gap, 0))
            || IsWithin(g_MouseCoords, rect.xy * hoverScale + vec2(rect.z * widthSquish + gap, -topAuxInfoRect.w), lastMapInfoSize)
            || IsWithin(g_MouseCoords, topAuxInfoRect.xy * hoverScale, topAuxInfoRect.zw)
            ;
        if (hoverAnim.Update(!closed && rawHover, _minViewWhenRecordsCollapsed ? 1.0 : mlDetector.slideProgress)) {
            DrawHoveredInterface(rect, fs, textHOffset, gap);
        } else {
            lastMapInfoSize = vec2();
        }
    }

    bool CheckClickNextTMX(bool down, int button) override {
        // check for middle mouse button
        if (!down || button != 2) return false;
        bool clicked = IsWithin(g_MouseCoords, auxInfoRect.xy, auxInfoRect.zw);
        if (clicked) {
            startnew(CoroutineFunc(OnClickNextTMX));
        }
        return clicked;
    }

    bool hasNextMapBeenTriggered = false;
    void OnClickNextTMX() {
        // don't allow this method to trigger more than once
        if (hasNextMapBeenTriggered) return;
        if (AbortClickNextTMX()) return;
        int nextID = TrackID;
        int count = 0;
        try {
            while (nextID == TrackID) {
                nextID = MapMonitor::GetNextMapByTMXTrackID(TrackID);
                count++;
                trace('Got next id: ' + nextID + ' for trackID ' + TrackID);
                if (nextID == TrackID) {
                    if (count > 5) {
                        throw('Failed 5 times to get next map but got the same ID each time');
                    }
                    NotifyError("Got the same ID (" + nextID + ") for next map as the current ID (" + TrackID + ") -- Retrying in 1s...");
                    sleep(1000);
                }
            }
        } catch {
            NotifyError("Failed to get next map ID, try again or do manually. Sorry :(.\nException: " + getExceptionInfo());
            return;
        }
        if (hasNextMapBeenTriggered) return;
        hasNextMapBeenTriggered = true;
        NotifyGreen("Loading next TMX map: " + nextID + ".\nAlso copying to clipboard.");
        IO::SetClipboard(tostring(nextID));
        LoadMapNow("https://map-monitor.xk.io/maps/download/" + nextID);
    }

    bool AbortClickNextTMX() {
        string refuse = "Refusing to go to next map as ";
        auto app = GetApp();
        if (app.CurrentPlayground is null) {
            NotifyError(refuse + "you don't appear to be in a map.");
            return true;
        }
        if (app.PlaygroundScript is null) {
            NotifyError(refuse + "you are not in solo mode (so it looks like you're on a server).");
            return true;
        }
        auto cp = app.CurrentPlayground;
        if (cp.Players.Length != 1) {
            NotifyError(refuse + "could not check player race time.");
            return true;
        }
        auto player = cast<CSmPlayer>(cp.Players[0]);
        auto script = cast<CSmScriptPlayer>(player.ScriptAPI);
        auto cmap = app.Network.ClientManiaAppPlayground;
        bool isPlaying = cmap.UI.UISequence == CGamePlaygroundUIConfig::EUISequence::Playing;
        if (isPlaying && script.CurrentRaceTime > 120 * 1000) {
            NotifyError(refuse + "current race time is > 2 minutes; respawn to go to next map.");
            return true;
        }
        return false;
    }

    void Draw_TMXBelowRecords(vec4 auxInfoRect) {
        nvg::Scale(widthSquish, 1);
        nvg::Scissor(auxInfoRect.x, auxInfoRect.y, auxInfoRect.z, auxInfoRect.w);
        if (!_minViewWhenRecordsCollapsed) {
            nvg::Translate(vec2((1.0 - mainAnim.Progress) * auxInfoRect.z, 0));
        } else {
            nvg::Translate(vec2(0, mainAnim.Progress ));
        }
        nvg::BeginPath();
        DrawBgRect(auxInfoRect.xy, auxInfoRect.zw);
        nvg::ClosePath();
        nvg::FillColor(vec4(1.0, 1, 1, 1));
        nvg::Text(auxInfoRect.xy + auxInfoRect.zw * vec2(.5, .55), "TMX: " + TrackIDStr);
        nvg::ResetScissor();
        nvg::ResetTransform();
    }

    void Draw_MedalsBelowRecords() {
        nvg::Scale(widthSquish, 1);
        nvg::Scissor(medalsInfoRect.x, medalsInfoRect.y, medalsInfoRect.z, medalsInfoRect.w);
        if (!_minViewWhenRecordsCollapsed) {
            nvg::Translate(vec2((1.0 - mainAnim.Progress) * medalsInfoRect.z, 0));
        }
        nvg::BeginPath();
        DrawBgRect(medalsInfoRect.xy, medalsInfoRect.zw);
        nvg::ClosePath();
        _Draw_MedalsBelowRecords_Inner();
        nvg::ResetScissor();
        nvg::ResetTransform();
    }

    void _Draw_MedalsBelowRecords_Inner() {
        float topBottomPad = 0.025;
        float topOffset = 0.025;
        uint drawnRows = 0;

        float nbRows = (S_DrawOnly2MedalsBelowRecords ? 1. : 2.);
        bool drawPbs = S_ShowPbDeltaToMedals && PersonalBestTime > 0;
        nbRows *= drawPbs ? 2.0 : 1.0;
        if (drawPbs && S_HideMedalsWorseThanPb) nbRows = Math::Min(float(PersonalBestMedal + 1), nbRows);
        nbRows = Math::Max(1.0, Math::Min(nbRows, S_MaxMedalRowsNb));
        float rowDelta = (1.0 - (topBottomPad * 2. + topOffset)) / (nbRows);
        float yPropNextRow = topBottomPad + topOffset + rowDelta / 2.0;
        // float yPropFirstRow = S_DrawOnly2MedalsBelowRecords ? (.5 + .025) : (.28 + .025);
        float col1Pos = .29;
        float col2Pos = .71;
        float oddMedalsXPos = drawPbs ? col1Pos : col2Pos;

        nvg::FillColor(OrderedMedalColors[0]);
        nvg::Text(medalsInfoRect.xy + medalsInfoRect.zw * vec2(col1Pos, yPropNextRow), OrderedMedalTimes[0]);
        if (drawPbs) _DrawPbDelta(col2Pos, yPropNextRow, OrderedMedalTimesUint[0]);
        if (drawPbs && S_HideMedalsWorseThanPb && PersonalBestMedal == 0) return;
        if (drawPbs) {
            yPropNextRow += rowDelta;
            drawnRows++;
        }
        if (S_MaxMedalRowsNb == drawnRows) return;

        nvg::FillColor(OrderedMedalColors[1]);
        nvg::Text(medalsInfoRect.xy + medalsInfoRect.zw * vec2(oddMedalsXPos, yPropNextRow), OrderedMedalTimes[1]);
        if (drawPbs) _DrawPbDelta(col2Pos, yPropNextRow, OrderedMedalTimesUint[1]);
        if (S_HideMedalsWorseThanPb && PersonalBestMedal == 1) return;
        yPropNextRow += rowDelta;
        drawnRows++;
        if (S_MaxMedalRowsNb == drawnRows) return;

        if (!S_DrawOnly2MedalsBelowRecords) {
            nvg::FillColor(OrderedMedalColors[2]);
            nvg::Text(medalsInfoRect.xy + medalsInfoRect.zw * vec2(col1Pos, yPropNextRow), OrderedMedalTimes[2]);
            if (drawPbs) _DrawPbDelta(col2Pos, yPropNextRow, OrderedMedalTimesUint[2]);
            if (drawPbs && S_HideMedalsWorseThanPb && PersonalBestMedal == 2) return;
            if (drawPbs) {
                yPropNextRow += rowDelta;
                drawnRows++;
            }
            if (S_MaxMedalRowsNb == drawnRows) return;

            nvg::FillColor(OrderedMedalColors[3]);
            nvg::Text(medalsInfoRect.xy + medalsInfoRect.zw * vec2(oddMedalsXPos, yPropNextRow), OrderedMedalTimes[3]);
            if (drawPbs) _DrawPbDelta(col2Pos, yPropNextRow, OrderedMedalTimesUint[3]);
        }
    }

    void _DrawPbDelta(float xPos, float yPropNextRow, uint medalTime) {
        bool isNeg = int(medalTime) < PersonalBestTime;
        nvg::FillColor(isNeg ? S_DeltaColorPositive : S_DeltaColorNegative);
        nvg::Text(medalsInfoRect.xy + medalsInfoRect.zw * vec2(xPos, yPropNextRow), (isNeg ? "+" : "-") + Time::Format(Math::Abs(int(PersonalBestTime) - int(medalTime)), true, false));
    }

    void Draw_MapNameAuthorAboveRecords(float gap) {
        nvg::Scale(widthSquish, 1);
        nvg::Scissor(topAuxInfoRect.x, topAuxInfoRect.y, topAuxInfoRect.z, topAuxInfoRect.w);
        if (!_minViewWhenRecordsCollapsed) {
            nvg::Translate(vec2((1.0 - mainAnim.Progress) * topAuxInfoRect.z, 0));
        }

        nvg::BeginPath();
        DrawBgRect(topAuxInfoRect.xy, topAuxInfoRect.zw);
        nvg::ClosePath();

        auto midPoint = topAuxInfoRect.xy + topAuxInfoRect.zw * vec2(.5, .55);
        auto midPointUpper = topAuxInfoRect.xy + topAuxInfoRect.zw * vec2(.5, .28);
        auto midPointLower = topAuxInfoRect.xy + topAuxInfoRect.zw * vec2(.5, .72);

        nvg::FillColor(vec4(1.0, 1, 1, 1));

        bool drawBoth = S_DrawTitleAuthorAboveRecords == AboveRecChoice::Both;
        bool drawName = drawBoth || S_DrawTitleAuthorAboveRecords == AboveRecChoice::Only_Map_Name;
        bool drawAuthor = drawBoth || S_DrawTitleAuthorAboveRecords == AboveRecChoice::Only_Author;
        if (drawName) {
            auto nameBounds = nvg::TextBounds(CleanName);
            auto xScale = Math::Clamp(Math::Min(nameBounds.x, topAuxInfoRect.z - gap * 2.) / Math::Max(1.0, nameBounds.x), 0.01, 1.0);
            nvg::Scale(xScale, 1);
            nvg::Text((drawBoth ? midPointUpper : midPoint) / vec2(xScale, 1), CleanName);
            nvg::Scale(1.0 / xScale, 1);
        }
        if (drawAuthor) {
            nvg::FillColor(vec4(.5, .5, .5, 1));
            nvg::Text(drawBoth ? midPointLower : midPoint, "by " + (S_AuthorCurrentName && AuthorCurrentName.Length > 0 ? AuthorCurrentName : AuthorDisplayName));
        }

        nvg::ResetScissor();
        nvg::ResetTransform();
    }

    void Draw_LoadingScreen() {
        if (!S_ShowLoadingScreenInfo) return;

        string[] lines;
        lines.InsertLast(g_MapInfo.Name);
        lines.InsertLast("by " + Text::OpenplanetFormatCodes(S_AuthorCurrentName && g_MapInfo.AuthorCurrentName.Length > 0 ? g_MapInfo.AuthorCurrentName : g_MapInfo.AuthorDisplayName));
        lines.InsertLast("");
        lines.InsertLast("Published: " + g_MapInfo.DateStr);

        if (TOTDStr.Length > 0)
            lines.InsertLast("TOTD: " + TOTDStr);
        lines.InsertLast("# Finishes: " + NbPlayersStr);
        if (S_ShowWhichTime == ShowTimeSetting::Worst_Time)
            lines.InsertLast("Worst Time: " + WorstTimeStr);
        else if (S_ShowWhichTime == ShowTimeSetting::Author_Time)
            lines.InsertLast("Author Time: " + AuthorTimeStr);
        lines.InsertLast("TMX: " + TrackIDStr);

        if (ShouldDrawTMXAwards)
            lines.InsertLast("TMX Awards: " + TMXAwards);
        if (ShouldDrawTMXTags)
            lines.InsertLast("TMX Tags: " + TMXMapTags);

        auto bls = Meta::GetPluginFromID("BetterLoadingScreen");
        auto sls = Meta::GetPluginFromID("static-loading-screen");
        bool drawOverBLS = (bls !is null && bls.Enabled) || (sls !is null && sls.Enabled);

        vec2 screen = vec2(Draw::GetWidth(), Math::Max(1, Draw::GetHeight()));
        float fs = drawOverBLS ? 40.0 : (fontProp * screen.y);
        float yTop = screen.y * S_LoadingScreenYOffsetPct / 100.0;
        float gap = fs / 4.0;
        // 0.069 = 100/1440
        float lineHeight = fs + gap;
        float height = gap + lines.Length * lineHeight;
        vec4 bgRect = vec4(0, yTop, screen.x, height);
        vec2 pos = vec2((Math::Max(0, screen.x / Math::Max(screen.y, 1.0) - 1.77777777) / 2. + 0.069) * screen.y, yTop + gap);

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
        bool drawAwards = ShouldDrawTMXAwards;
        bool drawTags = ShouldDrawTMXTags;

        // ! should match the number of calls to DrawDataLabels
        int nbRows = 9;
        if (!drawTotd) nbRows--;
        if (!drawAwards) nbRows--;
        if (!drawTags) nbRows--;

        nvg::BeginPath();

        vec2 tl = rect.xyz.xy + vec2(rect.z + gap, 0) - vec2(0, topAuxInfoRect.w);
        float rowsHeight = yStep * nbRows + xPad * 0.5;
        float fullWidth = HI_MaxCol1 + HI_MaxCol2 + xPad * 4.0;
        float thumbnailFrameHeight = Math::Min(fullRecordsHeight * screen.y + extraHeightBelowRecords + topAuxInfoRect.w - rowsHeight, fullWidth);
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
        pos = DrawDataLabels(pos.xyz.xy, col, yStep, col2X, fs, "Author", (S_AuthorCurrentName && AuthorCurrentName.Length > 0 ? AuthorCurrentName : AuthorDisplayName), null, 1.0, TMioAuthorButton, tmIOLogo, flagTexture);
        authorBtnPos += vec2(col2X + pos.w + xPad, -fs * 0.05);
        // pos = DrawDataLabels(pos.xyz.xy, col, yStep, col2X, fs, "Author WSID", AuthorWebServicesUserId);
        // pos = DrawDataLabels(pos.xyz.xy, col, yStep, col2X, fs, "Author AcctID", AuthorAccountId);
        pos = DrawDataLabels(pos.xyz.xy, col, yStep, col2X, fs, "Published", DateStr, null, 1.0, TMioButton, tmIOLogo);
        if (drawTotd)
            pos = DrawDataLabels(pos.xyz.xy, col, yStep, col2X, fs, "TOTD", TOTDStr);
        pos = DrawDataLabels(pos.xyz.xy, col, yStep, col2X, fs, "# Finishes", NbPlayersStr + " (" + TodaysDate + ")");

        bool showWtNotAt = S_ShowWhichTime == ShowTimeSetting::Worst_Time;
        string _wtLabel = showWtNotAt ? "Worst Time" : "Author Time";
        pos = DrawDataLabels(pos.xyz.xy, col, yStep, col2X, fs, _wtLabel, showWtNotAt ? WorstTimeStr : AuthorTimeStr);

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

        if (ShouldDrawTMXAwards)
            pos = DrawDataLabels(pos.xyz.xy, col, yStep, col2X, fs, Icons::Trophy + " Awards", TMXAwardsStr, null, alpha);
        if (ShouldDrawTMXTags)
            pos = DrawDataLabels(pos.xyz.xy, col, yStep, col2X, fs, "Tags", TMXMapTags, null, alpha);

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

    void Draw_PersistentUI() {
        if (!S_ShowPersistentUI) return;

        UI::SetNextWindowSize(800, 500, UI::Cond::FirstUseEver);
        if (UI::Begin("\\$8f0" + Icons::Map + "\\$z " + Name + " \\$666by\\$z " + (S_AuthorCurrentName && AuthorCurrentName.Length > 0 ? AuthorCurrentName : AuthorDisplayName) + "###MapInfoPersistent", S_ShowPersistentUI, UI::WindowFlags::AlwaysAutoResize)) {
            if (UI::BeginTable("mapInfoPersistent", 2, UI::TableFlags::SizingFixedFit)) {
                UI::TableSetupColumn("key", UI::TableColumnFlags::WidthFixed);
                UI::TableSetupColumn("value", UI::TableColumnFlags::WidthStretch);

                if (SP_ShowPubDate)    PersistentTableRowStr("Published", DateStr);
                if (TOTDDaysAgo >= 0 && SP_ShowTotDDate)   PersistentTableRowStr("TotD", TOTDStr);
                if (SP_ShowAuthorTime) PersistentTableRowStr("Author Time", "\\$080" + Icons::Circle + "\\$z " + AuthorTimeStr);
                if (SP_ShowNbPlayers)  PersistentTableRowStr("Players", NbPlayersStr);
                if (SP_ShowWorstTime)  PersistentTableRowStr("Worst Time", WorstTimeStr);
                if (SP_ShowTMXDojo)    PersistentTableRowStr("TMX ID", TrackIDStr);
                if (SP_ShowTMXAwards)  PersistentTableRowStr("TMX Awards", TMXAwardsStr);
                if (SP_ShowTMXMapTags) PersistentTableRowStr("TMX Tags", TMXMapTags);
                if (SP_ShowMapComment) PersistentTableRowStr("Map Comment", MapComment);

                if (UI::Button("TM.IO##pw")) OnClickTMioButton();
                UI::SameLine();
                UI::BeginDisabled(TrackID <= 0);
                if (UI::Button("TMX##pw")) OnClickTmxButton();
                UI::SameLine();
                UI::EndDisabled();
                if (UI::Button("TMDojo##pw")) OnClickTMDojoButton();

                UI::EndTable();
            }
        }
        UI::End();
    }

    void PersistentTableRowStr(const string &in key, const string &in value) {
        UI::PushID(key);

        UI::TableNextRow();
        UI::TableNextColumn();
        UI::Text(key);
        UI::TableNextColumn();
        UI::TextWrapped(value);

        UI::PopID();
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
                DebugTableRowStr("MapComment", MapComment);

                DebugTableRowStr("AuthorAccountId", AuthorAccountId);
                DebugTableRowStr("AuthorCurrentName", AuthorCurrentName);
                DebugTableRowStr("AuthorDisplayName", AuthorDisplayName);
                DebugTableRowStr("AuthorWebServicesUserId", AuthorWebServicesUserId);
                DebugTableRowStr("AuthorCountryFlag", AuthorCountryFlag);
                DebugTableRowStr("FileName", FileName);
                DebugTableRowStr("FileUrl", FileUrl);
                DebugTableRowStr("ThumbnailUrl", ThumbnailUrl);
                DebugTableRowStr("DateStr", DateStr);
                DebugTableRowUint("TimeStamp", TimeStamp);
                DebugTableRowUint("AuthorScore", AuthorScore);
                DebugTableRowUint("GoldScore", GoldScore);
                DebugTableRowUint("SilverScore", SilverScore);
                DebugTableRowUint("BronzeScore", BronzeScore);
                DebugTableRowUint("ChampionScore", ChampionScore);
                DebugTableRowUint("WarriorScore", WarriorScore);

                DebugTableRowInt("UploadedToNadeo", UploadedToNadeo);
                DebugTableRowButton("TMioButton", TMioButton);
                DebugTableRowButton("TMioAuthorButton", TMioAuthorButton);
                DebugTableRowStr("tm.io URL", GetTMioURL());

                DebugTableRowInt("UploadedToTMX", UploadedToTMX);
                DebugTableRowInt("TMXAuthorID", TMXAuthorID);
                DebugTableRowInt("TrackID", TrackID);
                DebugTableRowStr("TrackIDStr", TrackIDStr);

                DebugTableRowInt("TMXAwards", TMXAwards);
                DebugTableRowStr("TMXAwardsStr", TMXAwardsStr);
                DebugTableRowStr("TMXMapTags", TMXMapTags);

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
