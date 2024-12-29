namespace TMX {
    dictionary@ mapTags = dictionary();
    const string getMapByUidEndpoint_Old = "https://trackmania.exchange/api/maps/get_map_info/uid/{id}";
    const string getMapByUidEndpoint = "https://trackmania.exchange/api/maps?uid={id}&fields=Authors,MapId,AwardCount,Tags";
    const string getTagsEndpoint = "https://trackmania.exchange/api/tags/gettags";

    // <https://api2.mania.exchange/Method/Index/37>
    Json::Value@ GetMapFromUid(const string &in uid) {
        string url = getMapByUidEndpoint.Replace("{id}", uid);
        auto req = PluginGetRequest(url);
        req.Start();
        while (!req.Finished()) yield();
        if (req.ResponseCode() >= 400 || req.ResponseCode() < 200 || req.Error().Length > 0) {
            log_warn("[status:" + req.ResponseCode() + "] Error getting map by UID from TMX: " + req.Error() + " - " + url);
            return null;
        }
        // log_info("Debug tmx get map by uid: " + req.String());
        auto j = Json::Parse(req.String());
        @j = j["Results"];
        if (j !is null && j.GetType() == Json::Type::Array && j.Length == 1) {
            return j[0];
        }
        return j;
    }

    void OpenTmxTrack(int TrackID) {
#if DEPENDENCY_MANIAEXCHANGE
        try {
            if (S_OpenTmxInManiaExchange && Meta::GetPluginFromID("ManiaExchange").Enabled) {
                ManiaExchange::ShowMapInfo(TrackID);
                return;
            }
        } catch {}
#endif
        OpenBrowserURL("https://trackmania.exchange/maps/" + TrackID);
    }

    void OpenTmxAuthor(int TMXAuthorID) {
#if DEPENDENCY_MANIAEXCHANGE
        try {
            if (S_OpenTmxInManiaExchange && Meta::GetPluginFromID("ManiaExchange").Enabled) {
                ManiaExchange::ShowUserInfo(TMXAuthorID);
                return;
            }
        } catch {}
#endif
        OpenBrowserURL("https://trackmania.exchange/user/profile/" + TMXAuthorID);
    }

    void LoadMapTags() {
        auto req = PluginGetRequest(getTagsEndpoint);
        req.Start();
        while (!req.Finished()) yield();
        if (req.ResponseCode() >= 400 || req.ResponseCode() < 200 || req.Error().Length > 0) {
            log_warn("[status:" + req.ResponseCode() + "] Error getting Map Tags from TMX: " + req.Error());
            return;
        }

        Json::Value@ jsonMapTags = Json::Parse(req.String());

        for(uint i = 0; i < jsonMapTags.Length; i++) {
            string id = tostring(int(jsonMapTags[i]['ID']));
            string name = jsonMapTags[i]['Name'];
            mapTags.Set(id, name);
        }
    }
}


string[]@ GetTmxMapTagIds(Json::Value@ j) {
    string[]@ tagIds = {};
    try {
        auto tags = j["Tags"];
        for (uint i = 0; i < tags.Length; i++) {
            tagIds.InsertLast(tostring(int(tags[i]['TagId'])));
        }
    } catch {
        log_warn("Exception getting TMX map tags: " + getExceptionInfo());
    }
    return tagIds;
}



/**
 OLD RESPONSE:

  {"AuthorTime":24101,"ReplayWRTime":21764,"Length":1,"EmbeddedItemsSize":445390,"TypeName":"Race","UpdatedAt":"2024-12-23T18:39:13.743","Laps":1,"ReplayWRUserID":164777,"MapType":"TM_Race","Unreleased":false,"RouteName":"Single","DisplayCost":1783,"ParserVersion":4,"TitlePack":"TMStadium","ActivityAt":"2024-12-23T19:02:46.43","TrackValue":50000,"ReplayWRUsername":"Mael_27","Downloadable":true,"Unlisted":false,"GbxMapName":"Flight","IsMP4":true,"AwardCount":0,"TrackID":215376,"CommentCount":0,"UserID":21,"Environment":1,"ExeVersion":"3.3.0","HasThumbnail":true,"Mood":"Day","VideoCount":0,"HasGhostBlocks":true,"ReplayWRID":227347,"EnvironmentName":"Stadium","Name":"Flight","VehicleName":"","Vehicle":1,"Difficulty":1,"ModName":null,"Routes":0,"UnlimiterRequired":false,"ExeBuild":"2024-12-04_12_20","EmbeddedObjectsCount":17,"ReplayCount":3,"ReplayType":2,"Tags":"15,16,25","Username":"Ubisoft Nadeo","UserRecord":null,"DifficultyName":"Intermediate","HasScreenshot":true,"StyleName":null,"ImageCount":1,"Lightmap":8,"LengthName":"30 secs","TrackUID":"PUZW_cmHUVuX6S7Sg5v5AUxBxP1","SizeWarning":false,"Type":0,"AuthorCount":1,"Comments":"Map 2 of 5 for Week 2 of Weekly Shorts.\r\nBuilt by Hylis.\r\n\r\nFor the week starting December 22, 2024\r\n\r\nhttps://www.trackmania.com/news/8431","MappackID":0,"AuthorLogin":"Nadeo","UploadedAt":"2024-12-23T18:39:13.743"}


 */
;
