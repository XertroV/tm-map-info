// int g_NvgFont = nvg::LoadFont("fonts/Montserrat-BoldItalic.ttf", true, true);
int g_NvgFont = nvg::LoadFont("fonts/Montserrat-SemiBoldItalic.ttf", true, true);
UI::Font@ g_ImguiFont;

void Main() {
    if (Meta::GetPluginFromID("BetterLoadingScreen") !is null && S_ShowLoadingScreenInfo) {
        // we only need to use imgui fonts if BLS is installed, as it renders atop the nvg layer. if
        // BLS isn't installed, we can use more-performant nvg rendering
        @g_ImguiFont = UI::LoadFont("fonts/Montserrat-SemiBoldItalic.ttf", 40.f);
    }
    startnew(ClearTaskCoro);
    startnew(TOTD::LoadTOTDs);
}

/** Called every frame. `dt` is the delta time (milliseconds since last frame).
*/
void Update(float dt) {
    CheckForNewMap();
}

void Render() {
    if (g_MapInfo !is null) {
        g_MapInfo.Draw();
        // g_MapInfo.Draw_DebugUI();

        auto loadProgress = GetApp().LoadProgress;
        if (loadProgress !is null && loadProgress.State != NGameLoadProgress_SMgr::EState::Disabled) {
            g_MapInfo.Draw_LoadingScreen();
        }

    }
}

const string MenuLabel = "\\$8f0" + Icons::Map + "\\$z " + Meta::ExecutingPlugin().Name;

void RenderMenu() {
    if(UI::MenuItem(MenuLabel, "", S_ShowMapInfo)) {
        S_ShowMapInfo = !S_ShowMapInfo;
    }
}

void OnSettingsChanged() {
    if (S_ShowLoadingScreenInfo) @g_ImguiFont = UI::LoadFont("fonts/Montserrat-SemiBoldItalic.ttf", 40.f);
}

const string FmtTimestamp(uint64 timestamp) {
    // return Time::FormatString("%c", timestamp);
    return Time::FormatString("%Y-%m-%d (%a) %H:%M", timestamp);
}

const string FmtTimestampUTC(uint64 timestamp) {
    return Time::FormatStringUTC("%Y-%m-%d (%a) %H:%M", timestamp);
}

const string FmtTimestampDateOnlyUTC(uint64 timestamp) {
    return Time::FormatStringUTC("%Y-%m-%d (%a)", timestamp);
}

bool IsWithin(vec2 pos, vec2 topLeft, vec2 size) {
    vec2 d1 = topLeft - pos;
    vec2 d2 = (topLeft + size) - pos;
    return (d1.x >= 0 && d1.y >= 0 && d2.x <= 0 && d2.y <= 0)
        || (d1.x <= 0 && d1.y <= 0 && d2.x >= 0 && d2.y >= 0)
        || (d1.x <= 0 && d1.y >= 0 && d2.x >= 0 && d2.y <= 0)
        || (d1.x >= 0 && d1.y <= 0 && d2.x <= 0 && d2.y >= 0)
        ;
}

vec2 g_MouseCoords;

/** Called whenever the mouse moves. `x` and `y` are the viewport coordinates.
*/
void OnMouseMove(int x, int y) {
    g_MouseCoords.x = x;
    g_MouseCoords.y = y;
    // trace('Updated mouse pos ' + Time::Now);
}
