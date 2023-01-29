
void DrawMapInfoUI() {
    if (!S_ShowMapInfo) return;
    if (GetApp().CurrentPlayground is null || GetApp().RootMap is null || GetApp().Editor !is null) return;

    // @todo: maybe do this with nvg instead?
    if (UI::Begin("\\$8f0" + Icons::Map + "\\$z Map Info", UI::WindowFlags::AlwaysAutoResize)) {

        // shitty debug view for now
        UI::BeginTable("mapInfoDebug", 2);

        string[] keys = mapInfo.GetKeys();
        for (uint i = 0; i < keys.Length; i++) {
            UI::TableNextRow();
            UI::TableNextColumn();
            UI::Text(keys[i]);
            UI::TableNextColumn();
            UI::Text(string(mapInfo[keys[i]]));
        }

        UI::EndTable();
    }
    UI::End();
}



string currentMapUid;
dictionary mapInfo;
MapInfo_UI@ g_MapInfo = null;

void CheckForNewMap() {
    CTrackMania@ app = cast<CTrackMania>(GetApp());
    string mapUid;
    if (app.CurrentPlayground is null || app.RootMap is null || app.Editor !is null) {
        mapUid = "";
    } else {
        mapUid = app.RootMap.MapInfo.MapUid;
    }

    if(mapUid != currentMapUid) {
        currentMapUid = mapUid;
        startnew(OnNewMap);
    }
}



void OnNewMap() {
    if (currentMapUid.Length == 0) {
        @g_MapInfo = null;
        return;
    } else {
        @g_MapInfo = MapInfo_UI();
    }
    CGameCtnChallenge@ map = GetApp().RootMap;
    if (map is null) return;

    mapInfo.DeleteAll();
    getNadeoMapData(map.MapInfo.MapUid);
    mapInfo.Set("Map UID", map.MapInfo.MapUid);
    mapInfo.Set("Name", string(map.MapInfo.Name));
    mapInfo.Set("Author nick", string(map.MapInfo.AuthorNickName));
    mapInfo.Set("Author login", map.MapInfo.AuthorLogin);

    if (isOnNadeoServices) {
        mapInfo.Set("Uploaded", Time::FormatString("%c", nadeoData["uploadTimestamp"]));
    }

    // if (totdTracks.Exists(map.MapInfo.MapUid)) {
    // 	mapInfo.Set("TOTD on", Time::FormatString("%c", uint64(totdTracks[map.MapInfo.MapUid])));
    // } else {
    // 	mapInfo.Set("TOTD on", "n/a");
    // }
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

    int UploadedToTMX = -1;
    int TrackID = -1;
    string TrackIDStr = "...";
    // When `null`, there's no TMX info. It should never be Json::Type::Null.
    Json::Value@ TMX_Info = null;

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

    MapInfo_Data() {
        auto map = GetApp().RootMap;
        if (map is null) throw("Cannot instantiate MapInfo_Data when RootMap is null.");
        uid = map.EdChallengeId;
        SetName(map.MapName);
        author = map.AuthorNickName;

        AuthorDisplayName = map.MapInfo.AuthorNickName;

        StartInitializationCoros();
    }

    void StartInitializationCoros() {
        startnew(CoroutineFunc(this.GetMapInfoFromCoreAPI));
        startnew(CoroutineFunc(this.GetMapInfoFromMapMonitorAPI));
        startnew(CoroutineFunc(this.GetMapTOTDStatus));
        startnew(CoroutineFunc(this.GetMapTMXStatus));
        startnew(CoroutineFunc(this.MonitorRecordsVisibility));
        startnew(CoroutineFunc(this.MonitorUIVisibility));
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

    void GetMapInfoFromMapMonitorAPI() {
        auto resp = MapMonitor::GetNbPlayersForMap(uid);
        NbPlayers = resp.Get('nb_players', 98765);
        WorstTime = resp.Get('last_highest_score', 0);

        NbPlayersStr = NbPlayers >= 10000 && NbPlayers % 1000 == 0 ? tostring(NbPlayers / 1000) + "k" : tostring(NbPlayers);
        WorstTimeStr = Time::Format(WorstTime);

        LoadedNbPlayers = true;
        trace('MapInfo_Data loaded nb players');

        float refreshInSeconds = resp.Get('refresh_in', 150.0);
        trace('Refreshing nb players in: ' + refreshInSeconds);
        sleep(int(refreshInSeconds * 1000.0));
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
        if (tmxTrack.GetType() == Json::Type::Object) {
            UploadedToTMX = 1;
            TrackID = int(tmxTrack.Get('TrackID', -1));
            TrackIDStr = tostring(TrackID);
            @TMX_Info = tmxTrack;
        } else {
            UploadedToTMX = 0;
            TrackIDStr = "Not Uploaded";
        }
    }

    bool IsGoodUISequence(CGamePlaygroundUIConfig::EUISequence uiSeq) {
        return uiSeq == CGamePlaygroundUIConfig::EUISequence::Playing
            || uiSeq == CGamePlaygroundUIConfig::EUISequence::Finish
            || uiSeq == CGamePlaygroundUIConfig::EUISequence::EndRound
            ;
    }

    private uint lastNbUilayers = 0;
    bool IsUIPopulated() {
        auto cmap = GetApp().Network.ClientManiaAppPlayground;
        auto cp = GetApp().CurrentPlayground;
        if (cmap is null || cp is null || cp.UIConfigs.Length == 0) return false;
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
        for (uint i = 2; i < Math::Min(8, cmap.UILayers.Length); i++) {
            auto layer = cmap.UILayers[i];
            if (layer !is null && layer.Type == CGameUILayer::EUILayerType::ScoresTable) {
                return layer.LocalPage !is null && layer.LocalPage.MainFrame !is null && layer.LocalPage.MainFrame.Visible;
            }
        }
        return false;
    }

    bool SettingsOpen() {
        auto vp = GetApp().Viewport;
        if (vp.Overlays.Length < 11) return false;
        // 5 normally, report/key have 15 and 24; menu open has like 390
        return vp.Overlays[10].m_CorpusVisibles.Length > 10;
    }

    bool ShouldDrawUI {
        get {
            return UI::IsGameUIVisible() && isRecordsElementVisible && !ScoreTableVisible() && !SettingsOpen();
        }
    }
    private bool isRecordsElementVisible = false;
    private void MonitorRecordsVisibility() {
        trace('test populated');
        while (!IsUIPopulated()) yield();
        trace('test safe');
        if (!IsSafeToCheckUI()) throw('unexpected');
        trace('is safe');
        // once we detect things have started to load, wait another second
        trace('sleep');
        for (uint i = 0; i < 10; i++) yield();
        trace('assert safe');
        while (!IsSafeToCheckUI()) yield(); // throw("Should only happen if we exit the map super fast.");
        trace('find UI elements');
        while (IsSafeToCheckUI() && !FindUIElements()) {
            sleep(100);
        }
        trace('done checking ui. found: ' + lastRecordsLayerIndex);
        while (true) {
            yield();
            if (GetApp().RootMap is null || GetApp().RootMap.EdChallengeId != uid) break;
            isRecordsElementVisible = IsSafeToCheckUI() && IsRecordElementVisible();
        }
        trace('exited');
    }

    protected bool _GameUIVisible = false;
    private void MonitorUIVisibility() {
        while (true) {
            yield();
            yield();
            yield();
            yield();
            yield();
            _GameUIVisible = UI::IsGameUIVisible();
        }
    }

    float slideFrameProgress = 1.0;

    private bool openedExploreNod = false;
    private bool IsRecordElementVisible() {
        auto cmap = GetApp().Network.ClientManiaAppPlayground;
        if (cmap is null) return false;
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
        auto slideFrame = frame.Controls[1];
        if (slideFrame.ControlId != "frame-slide") throw("should be slide-frame");
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
            // cost about 0.12 ms!
            // || !UI::IsGameUIVisible()
            ;
        if (closed) {
            lastMapInfoSize = vec2();
        }
        if (!mainAnim.Update(!closed, slideFrameProgress)) return;

        auto rect = UpdateBounds();

        float fs = fontProp * screen.y;
        float xPad = xPaddingProp * screen.y;
        float gap = gapProp * screen.y;
        string mainLabel = Icons::Users + " " + NbPlayersStr;

        nvg::Reset();

        nvg::FontFace(g_NvgFont);
        nvg::FontSize(fs);
        nvg::TextAlign(nvg::Align::Center | nvg::Align::Middle);

        auto textSize = nvg::TextBounds(mainLabel);
        float width = xPad * 2.0 + textSize.x;
        rect.x -= width;
        rect.z = width;
        float textHOffset = rect.w * .55 - textSize.y / 2.0;

        // animate sliding away when record UI opens/closes
        // first, set up a scissor similar to the records UI
        nvg::Scissor(rect.x, rect.y, rect.z, rect.w);
        // now, offset everything depending on slider progress
        nvg::Translate(vec2((1.0 - mainAnim.Progress) * rect.z, 0));
        // that's all we need.

        nvg::BeginPath();
        DrawBgRect(rect.xy, rect.zw);
        // nvg::Rect(rect.xy, rect.zw);
        // nvg::FillColor(vec4(0, 0, 0, .8));
        // nvg::Fill();

        nvg::FillColor(vec4(1.0));
        nvg::Text(rect.xy + rect.zw * vec2(.5, .55), mainLabel);

        nvg::ClosePath();

        // reset scissor so we can draw the hover
        nvg::ResetScissor();
        nvg::ResetTransform();

        bool rawHover = IsWithin(g_MouseCoords, rect.xy, rect.zw + vec2(gap, 0))
            || IsWithin(g_MouseCoords, rect.xy + vec2(rect.z + gap, 0), lastMapInfoSize);
            ;
        if (hoverAnim.Update(!closed && rawHover, slideFrameProgress)) {
            DrawHoveredInterface(rect, fs, xPad, textHOffset, gap);
        }
    }

    // in ms
    // float animDuration = 250.0;
    // bool lastHover = false;
    // float t_hover = 0.0;
    // float hoverSlide = 0.0;
    // uint lastHoverChange = 0;
    // uint lastHoverCheck = 0;
    // bool TrackHovering(bool hoverRaw) {
    //     if (lastHoverChange == 0) lastHoverChange = Time::Now;
    //     if (lastHoverCheck == 0) lastHoverCheck = Time::Now;

    //     float delta = float(int(Time::Now) - int(lastHoverCheck)) / animDuration;
    //     lastHoverCheck = Time::Now;

    //     float sign = hoverRaw ? 1.0 : -1.0;
    //     t_hover = Math::Clamp(t_hover + sign * delta, 0.0, 1.0);
    //     // float t_hover = Math::Clamp(float(int(Time::Now) - int(lastHoverChange)) / animDuration, 0.0, 1.0);
    //     // if (lastHover) t_hover = 1.0 - t_hover;
    //     if (lastHover != hoverRaw) {
    //         lastHover = hoverRaw;
    //         lastHoverChange = Time::Now;
    //     }
    //     hoverSlide = -(t_hover * (t_hover - 2.));
    //     // hoverSlide = 1.0;
    //     hoverSlide = Math::Min(slideFrameProgress, hoverSlide);
    //     return hoverSlide > 0.;
    // }

    float HoverInterfaceScale = 0.5357;
    float HI_MaxCol1 = 64.0;
    float HI_MaxCol2 = 64.0;
    vec2 lastMapInfoSize = vec2();

    void DrawHoveredInterface(vec4 rect, float fs, float xPad, float textHOffset, float gap) {
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
        nvg::FillColor(vec4(1, 1, 1, alpha));

        vec2 pos = tl + vec2(xPad, textHOffset + xPad * 0.5);

        // ! update nbRows if you add more DrawDataLabels

        pos = DrawDataLabels(pos, yStep, col2X, fs, "Name", CleanName, NvgName, alpha);
        // pos = DrawDataLabels(pos, yStep, col2X, fs, "Name", CleanName);
        pos = DrawDataLabels(pos, yStep, col2X, fs, "Author", AuthorDisplayName);
        // pos = DrawDataLabels(pos, yStep, col2X, fs, "Author WSID", AuthorWebServicesUserId);
        // pos = DrawDataLabels(pos, yStep, col2X, fs, "Author AcctID", AuthorAccountId);
        pos = DrawDataLabels(pos, yStep, col2X, fs, "Published", DateStr);
        if (drawTotd)
            pos = DrawDataLabels(pos, yStep, col2X, fs, "TOTD", TOTDStr);
        pos = DrawDataLabels(pos, yStep, col2X, fs, "Nb Players", NbPlayersStr);
        pos = DrawDataLabels(pos, yStep, col2X, fs, "Worst Time", WorstTimeStr);
        pos = DrawDataLabels(pos, yStep, col2X, fs, "TMX", TrackIDStr);

        pos.x -= xPad;

        if (ThumbnailTexture !is null) {
            vec2 size = vec2(thumbnailHeight, thumbnailHeight);
            vec2 tl = pos + vec2(fullWidth, 0) / 2.0 - vec2(size.x / 2.0, 0);
            nvg::ClosePath();
            nvg::BeginPath();
            nvg::Rect(tl, size);
            nvg::FillPaint(nvg::TexturePattern(tl, size, 0.0, ThumbnailTexture, 1.0));
            nvg::Fill();
        }

        nvg::ClosePath();
        nvg::ResetTransform();
    }



    void DrawBgRect(vec2 pos, vec2 size) {
        nvg::Rect(pos, size);
        nvg::FillColor(vec4(0, 0, 0, .85));
        nvg::Fill();
    }

    vec2 DrawDataLabels(vec2 pos, float yStep, float col2X, float fs, const string &in label, const string &in value, NvgText@ textObj = null, float alpha = 1.0) {
        HI_MaxCol1 = Math::Max(nvg::TextBounds(label).x, HI_MaxCol1);
        HI_MaxCol2 = Math::Max(nvg::TextBounds(value).x, HI_MaxCol2);
        nvg::Text(pos, label);
        if (textObj is null)
            nvg::Text(pos + vec2(col2X, 0), value);
        else
            textObj.Draw(pos + vec2(col2X, 0), vec3(1, 1, 1), fs, alpha);
        pos.y += yStep;
        return pos;
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
            DebugUITableRow("Nb Players:", NbPlayersStr);
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



/**
 * Parse a color string and provide a draw function so that we can draw colored text.
 */
class NvgText {
    string[]@ parts;
    vec3[] cols;

    NvgText(const string &in coloredText) {
        auto preText = ColoredString(StripNonColorFormatCodes(coloredText));
        @parts = preText.Split("\\$");
        uint startAt = 0;
        if (!preText.StartsWith("\\$")) {
            startAt = 1;
            cols.InsertLast(vec3(-1, -1, -1));
        }
        for (uint i = startAt; i < parts.Length; i++) {
            if (parts[i].Length == 0) {
                cols.InsertLast(vec3(-1, -1, -1));
                continue;
            }
            if (parts[i].SubStr(0, 1).ToLower() == "z") {
                parts[i] = parts[i].SubStr(1);
                cols.InsertLast(vec3(-1, -1, -1));
                continue;
            }
            auto hex = parts[i].SubStr(0, 3);
            parts[i] = parts[i].SubStr(3);
            cols.InsertLast(hexTriToRgb(hex));
        }
    }

    void Draw(vec2 pos, vec3 defaultCol, float fs, float alpha = 1.0) {
        float xOff = 0;
        for (uint i = 0; i < parts.Length; i++) {
            auto col = cols[i];
            if (col.x < 0) col = defaultCol;
            nvg::FillColor(vec4(col.x, col.y, col.z, alpha));
            auto xy = nvg::TextBounds(parts[i]);
            nvg::Text(pos + vec2(xOff, 0), parts[i]);
            xOff += Math::Max(0.0, xy.x - fs / 7.0);
        }
        nvg::FillColor(vec4(defaultCol.x, defaultCol.y, defaultCol.z, alpha));
    }
}


bool IsCharInt(int char) {
    return 48 <= char && char <= 57;
}

bool IsCharInAToF(int char) {
    return (97 <= char && char <= 102) /* lower case */
        || (65 <= char && char <= 70); /* upper case */
}

bool IsCharHex(int char) {
    return IsCharInt(char) || IsCharInAToF(char);
}

uint8 HexCharToInt(int char) {
    if (IsCharInt(char)) {
        return char - 48;
    }
    if (IsCharInAToF(char)) {
        int v = char - 65 + 10;  // A = 65 ascii
        if (v < 16) return v;
        return v - (97 - 65);    // a = 97 ascii
    }
    throw("HexCharToInt got char with code " + char + " but that isn't 0-9 or a-f or A-F in ascii.");
    return 0;
}

vec3 hexTriToRgb(const string &in hexTri) {
    if (hexTri.Length != 3) { throw ("hextri must have 3 characters. bad input: " + hexTri); }
    try {
        float r = HexCharToInt(hexTri[0]);
        float g = HexCharToInt(hexTri[1]);
        float b = HexCharToInt(hexTri[2]);
        return vec3(r, g, b) / 15.;
    } catch {
        throw("Exception while processing hexTri (" + hexTri + "): " + getExceptionInfo());
    }
    return vec3();
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
