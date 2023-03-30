namespace TOTD {
    bool initialized = false;
    bool totdQuickLoad = false;
    dictionary uidToTimestamp;
    dictionary uidToDate;
    dictionary uidToDaysAgo;

    int nextTotdTs;
    int nextTotdInSeconds;

    void LoadTOTDs() {
        if (initialized) return;

        auto resp = Live::GetTotdByMonth(totdQuickLoad ? 1 : 100);
        if (resp.GetType() != Json::Type::Object) {
            log_warn("LoadTOTDs got bad response: " + Json::Write(resp));
            sleep(10000);
            startnew(LoadTOTDs);
            return;
        }
        nextTotdTs = resp['nextRequestTimestamp'];
        nextTotdInSeconds = resp['relativeNextRequest'];
        startnew(LoadNextTOTD);
        Json::Value@ months = resp["monthList"];
        int daysAgo = 0;
        for (uint i = 0; i < months.Length; i++) {
            yield();
            // uint year = months[i]["year"];
            // uint month = months[i]["month"];
            auto @days = months[i]["days"];
            uint lastDay = months[i]["lastDay"];
            for (uint j = Math::Min(lastDay - 1, days.Length - 1); j < lastDay; j--) {
                auto @totd = months[i]["days"][j];
                string uid = totd["mapUid"];
                if (uid.Length == 0) continue;

                uidToTimestamp.Set(uid, totd["startTimestamp"]);
                uidToDate.Set(uid, FmtTimestampDateOnlyUTC(uint(totd["startTimestamp"])));
                if (!uidToDaysAgo.Exists(uid))
                    uidToDaysAgo.Set(uid, daysAgo);
                daysAgo++;
                // auto ts = uint(totd['startTimestamp']);
                // trace(tostring(ts) + ": " + FmtTimestamp(ts));
            }
        }
        initialized = true;
    }

    /** Sleeps until a new TOTD is ready */
    void LoadNextTOTD() {
        int sleepFor = Math::Min(nextTotdInSeconds, Math::Max(0, nextTotdTs - Time::Stamp));
        log_trace("Waiting before getting next TOTDs: " + sleepFor + " ms");
        sleep(sleepFor * 1000);
        log_trace("Getting new TOTDs...");
        initialized = false;
        totdQuickLoad = true;
        auto daysAgoKeys = uidToDaysAgo.GetKeys();
        for (uint i = 0; i < daysAgoKeys.Length; i++) {
            uidToDaysAgo[daysAgoKeys[i]] = 1 + int(uidToDaysAgo[daysAgoKeys[i]]);
        }
        if (g_MapInfo !is null) g_MapInfo.RefreshTOTDStatus();
        LoadTOTDs();
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

    int GetDaysAgo_Async(const string &in uid) {
        while (!initialized) yield();
        if (!uidToDaysAgo.Exists(uid)) return -1;
        return int(uidToDaysAgo[uid]);
    }
}
