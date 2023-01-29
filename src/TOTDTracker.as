namespace TOTD {
    bool initialized = false;
    dictionary uidToTimestamp;
    dictionary uidToDate;

    void LoadTOTDs() {
        if (initialized) return;

        auto resp = Live::GetTotdByMonth();
        if (resp.GetType() != Json::Type::Object) {
            warn("LoadTOTDs got bad response: " + Json::Write(resp));
            sleep(10000);
            startnew(LoadTOTDs);
            return;
        }
        Json::Value@ months = resp["monthList"];
        for (uint i = 0; i < months.Length; i++) {
            yield();
            // uint year = months[i]["year"];
            // uint month = months[i]["month"];
            for (int j = 0; j < months[i]["lastDay"]; j++) {
                auto @totd = months[i]["days"][j];
                // uint day = months[i]["days"][j]["monthDay"];
                // string dayStr = Text::Format("%d", year) + "-" + Text::Format("%d", month) + "-" + Text::Format("%d", day);
                uidToTimestamp.Set(totd["mapUid"], totd["startTimestamp"]);
                uidToDate.Set(totd["mapUid"], FmtTimestampDateOnlyUTC(uint(totd["startTimestamp"])));
                // auto ts = uint(totd['startTimestamp']);
                // trace(tostring(ts) + ": " + FmtTimestamp(ts));
            }
        }
        initialized = true;
    }

    /**
     * Returns "" if map was not a TOTD, otherwise a formatted date string.
     * This function will yield if TOTD data is not initialized.
     */
    const string GetDateMapWasTOTD_Async(const string &in uid) {
        while (!initialized) yield();
        if (!uidToDate.Exists(uid)) return "";
        return string(uidToDate[uid]);
        // return FmtTimestamp(uint64(uidToTimestamp[uid]));
    }
}
