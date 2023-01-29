
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



dictionary mapInfo;
string currentMapUid;

MapInfo_UI@ g_MapInfo = null;

void step() {
    CTrackMania@ app = cast<CTrackMania>(GetApp());
    string mapUid;
    if (app.CurrentPlayground is null || app.RootMap is null || app.Editor !is null) {
        mapUid = "";
    } else {
        mapUid = app.RootMap.MapInfo.MapUid;
    }

    if(mapUid != currentMapUid) {
        currentMapUid = mapUid;
        onNewMap();
    }
}



void onNewMap() {
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

    uint NbPlayers = LoadingNbPlayersFlag;
    uint WorstTime = 0;
    string NbPlayersStr = "";
    string WorstTimeStr = "";

    string TOTDDate = "";

    bool LoadedMapData = false;
    bool LoadedNbPlayers = false;
    bool LoadedWasTOTD = false;

    MapInfo_Data() {
        auto map = GetApp().RootMap;
        if (map is null) throw("Cannot instantiate MapInfo_Data when RootMap is null.");
        uid = map.EdChallengeId;
        Name = ColoredString(map.MapName);
        author = map.AuthorNickName;
        startnew(CoroutineFunc(this.GetMapInfoFromCoreAPI));
        startnew(CoroutineFunc(this.GetMapInfoFromMapMonitorAPI));
        startnew(CoroutineFunc(this.GetMapTOTDStatus));
    }

    void GetMapInfoFromCoreAPI() {
        // This should usually be near-instant b/c the game has probably already loaded this.
        auto info = Core::GetMapFromUid(uid);
        if (info is null) return;
        AuthorAccountId = info.AuthorAccountId;
        AuthorDisplayName = info.AuthorDisplayName;
        AuthorWebServicesUserId = info.AuthorWebServicesUserId;

        Name = ColoredString(info.Name);
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
    }

    void GetMapInfoFromMapMonitorAPI() {
        auto resp = MapMonitor::GetNbPlayersForMap(uid);
        NbPlayers = resp.Get('nb_players', 98765);
        WorstTime = resp.Get('last_highest_score', 0);

        NbPlayersStr = NbPlayers % 1000 == 0 ? tostring(NbPlayers / 1000) + " K" : tostring(NbPlayers);
        WorstTimeStr = Time::Format(WorstTime);

        LoadedNbPlayers = true;
        trace('MapInfo_Data loaded nb players');
    }

    void GetMapTOTDStatus() {
        TOTDDate = TOTD::GetDateMapWasTOTD_Async(uid);
        LoadedWasTOTD = true;
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

    void Draw() {
        if (!UI::IsGameUIVisible()) return;
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

        nvg::BeginPath();
        DrawBgRect(rect.xy, rect.zw);
        // nvg::Rect(rect.xy, rect.zw);
        // nvg::FillColor(vec4(0, 0, 0, .8));
        // nvg::Fill();

        nvg::FillColor(vec4(1.0));
        nvg::Text(rect.xy + rect.zw * vec2(.5, .55), mainLabel);

        nvg::ClosePath();

        if (IsWithin(g_MouseCoords, rect.xy, rect.zw)) {
            DrawHoveredInterface(rect, fs, xPad, textHOffset, gap);
        }

    }

    float HoverInterfaceScale = 0.75;
    float HI_MaxCol1 = 64.0;
    float HI_MaxCol2 = 64.0;

    void DrawHoveredInterface(vec4 rect, float fs, float xPad, float textHOffset, float gap) {
        fs *= HoverInterfaceScale;
        xPad *= HoverInterfaceScale;
        textHOffset *= HoverInterfaceScale;

        float newMax1 = 0.0;
        float newMax2 = 0.0;

        float yStep = rect.w * HoverInterfaceScale;
        nvg::TextAlign(nvg::Align::Top | nvg::Align::Left);
        nvg::FontSize(fs);

        int nbRows = 6;

        nvg::BeginPath();

        vec2 tl = rect.xy + vec2(rect.z + gap, 0);
        DrawBgRect(tl, vec2(HI_MaxCol1 + HI_MaxCol2 + xPad * 4.0, yStep * nbRows));
        float col2X = HI_MaxCol1 + xPad * 3.0;

        HI_MaxCol1 = 0.0;
        HI_MaxCol2 = 0.0;

        nvg::FillColor(vec4(1.0));
        vec2 pos = tl + vec2(xPad, textHOffset);
        pos = DrawDataLabels(pos, yStep, col2X, "Name", Name);
        pos = DrawDataLabels(pos, yStep, col2X, "Author", AuthorDisplayName);
        // pos = DrawDataLabels(pos, yStep, col2X, "Author WSID", AuthorWebServicesUserId);
        // pos = DrawDataLabels(pos, yStep, col2X, "Author AcctID", AuthorAccountId);
        pos = DrawDataLabels(pos, yStep, col2X, "Published", DateStr);
        pos = DrawDataLabels(pos, yStep, col2X, "TOTD", TOTDDate.Length > 0 ? TOTDDate : "--");
        pos = DrawDataLabels(pos, yStep, col2X, "Nb Players", NbPlayersStr);
        pos = DrawDataLabels(pos, yStep, col2X, "Worst Time", WorstTimeStr);

        nvg::ClosePath();
    }

    void DrawBgRect(vec2 pos, vec2 size) {
        nvg::Rect(pos, size);
        nvg::FillColor(vec4(0, 0, 0, .8));
        nvg::Fill();
    }

    vec2 DrawDataLabels(vec2 pos, float yStep, float col2X, const string &in label, const string &in value) {
        HI_MaxCol1 = Math::Max(nvg::TextBounds(label).x, HI_MaxCol1);
        HI_MaxCol2 = Math::Max(nvg::TextBounds(value).x, HI_MaxCol2);
        nvg::Text(pos, label);
        nvg::Text(pos + vec2(col2X, 0), value);
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
            DebugUITableRow("TOTD:", TOTDDate.Length > 0 ? TOTDDate : "--");
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
