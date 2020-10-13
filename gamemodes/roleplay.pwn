// Config diutamakan
#define     MAX_PASSWORD        64
#define     MAX_SALT            32

// Set jadi lebih tinggi, tapi jangan
// lebih dari 4028 biar ga corrupt
#define     MAX_STR_SAVE_QUERY  1500

// Sesuaikan sama yang di server.cfg
// biar ga close sendiri gamemodenya
#define     MAX_PLAYERS         50   

#include <a_samp>
#include <a_mysql>

#include <sscanf2>
#include <foreach>
#include <Pawn.CMD>

// something
forward MySQL:ConnectFrom(const file[]);
forward InitializeMySQL();
forward SavePlayerToDatabase(playerid);

forward OnQueryReceived(playerid, threadid);
forward OnPlayerCheck(playerid);

enum E_PLAYER_DATA {
    pId,
    pName[MAX_PLAYER_NAME + 1],
    pPass[MAX_PASSWORD + 1],
    pSalt[MAX_SALT + 1],
    pWrongPass,
    pRegistered,
    pSpawned,
    Float:pPosX,
    Float:pPosY,
    Float:pPosZ,
    Float:pPosA,
    pInterior,
    pVirtualWorld
};

// Global Enum
enum {
    /* Structures Dialog */
    E_DIALOG_NONE = 0,
    E_DIALOG_LOGIN,
    E_DIALOG_REGISTER,

    /* Structures Threadid */
    E_THREAD_NONE = 32769,
    E_THREAD_FIND_NICKNAME,
    E_THREAD_LOGIN,
    E_THREAD_REGISTER,
    E_THREAD_LOAD_USER
};

// playerdata/info bebas
new PlayerData[MAX_PLAYERS][E_PLAYER_DATA];

main() {
    // Crash gamemode kalau MAX_PLAYERS gak cocok sama server.cfg
    assert(MAX_PLAYERS == GetMaxPlayers());
    print("Gamemode by you");
}

public MySQL:ConnectFrom(const file[]) {
    if (fexist(file)) {
        new 
            SQL_HOST[16],
            SQL_USER[25],
            SQL_PASS[32],
            SQL_BASE[32];

        new 
            File:fhandle = fopen(file, io_read),
            bHoldString[128], lines, at, offset;

        while (fread(fhandle, bHoldString)) lines++;

        at = lines - 10;
        lines = 0;

        fseek(fhandle);

        while ((offset = fread(fhandle, bHoldString)))
        {
            if (++lines <= at) continue;
            if (bHoldString[0] == '#') continue;

            if (bHoldString[offset - 2] == '\r') bHoldString[offset - 2] = EOS;
            else if (bHoldString[offset - 1] == '\n') bHoldString[offset - 2] = EOS;
            
            if (strfind(bHoldString, "hostname", true) != -1) {
                new 
                    postFile = (strfind(bHoldString, "= ", true) + 1);

                format(SQL_HOST, sizeof SQL_HOST, bHoldString[postFile + 1]);
            }
            if (strfind(bHoldString, "username", true) != -1) {
                new 
                    postFile = (strfind(bHoldString, "= ", true) + 1);

                format(SQL_USER, sizeof SQL_USER, bHoldString[postFile + 1]);
            }
            if (strfind(bHoldString, "password", true) != -1) {
                new 
                    postFile = (strfind(bHoldString, "= ", true) + 1);

                if (bHoldString[postFile + 1] != ' ') {
                    format(SQL_PASS, sizeof SQL_PASS, bHoldString[postFile + 1]);
                }
            }
            if (strfind(bHoldString, "database", true) != -1) {
                new 
                    postFile = (strfind(bHoldString, "= ", true) + 1);

                format(SQL_BASE, sizeof SQL_BASE, bHoldString[postFile + 1]);
            }
        }
        return mysql_connect(SQL_HOST, SQL_USER, SQL_PASS, SQL_BASE);        
    }
    return MYSQL_INVALID_HANDLE;
}

public InitializeMySQL() {
    new 
        errno;

    if((connHandle = SQL_connectFrom("MySQL/config.dex")) == MYSQL_INVALID_HANDLE || (errno = mysql_errno(connHandle)) != 0) {
        new 
            errHandle[100];

        mysql_error(errHandle, sizeof (errHandle), connHandle);
        printf("ERROR %d: %s", errno, errno == -1 ? errHandle : "Invalid MySQL Handle");
        return 0;
    }
    print("Connected to databases!");
    return 1;
}

public SavePlayerToDatabase(playerid) {
    new 
        strQuery[MAX_STR_SAVE_QUERY];

    mysql_format(connHandle, strQuery, sizeof strQuery, "UPDATE players SET PosX = '%.4f', PosY = '%.4f', PosZ = '%.4f', PosA = '%.4f', Interior = '%i', VirtualWorld = '%i' WHERE ID = '%i'",
        PlayerData[playerid][pPosX],
        PlayerData[playerid][pPosY],
        PlayerData[playerid][pPosZ],
        PlayerData[playerid][pInterior],
        PlayerData[playerid][pVirtualWorld],
        PlayerData[playerid][pId]    
    );
    mysql_query(connHandle, strQuery, false);
    return 1;
}

public OnGameModeInit() {
    SetupGamemode();
    return 1;
}

public OnPlayerConnect(playerid) {
    ResetPlayerVariable(playerid);
    return 1;
}

public OnPlayerRequestClass(playerid, classid) {
    new 
        hr, mt, sec;
    
    gettime(hr, mt, sec);
    SetPlayerTime(playerid, hr, mt);
    TogglePlayerSpectating(playerid, true);

    SetTimerEx(#OnPlayerCheck, 800, false, "i", playerid);
    return 1;
}

public OnPlayerCheck(playerid) {
    SetPlayerCamera(playerid);
    
    new strQuery[64];
    mysql_format(sqlHandle, strQuery, sizeof strQuery, "SELECT * FROM players WHERE nickname = '%e' LIMIT 1",
        ret_GetPlayerName(playerid);
    );
    mysql_tquery(sqlHandle, strQuery, #OnQueryReceived, "ii", playerid, THREAD_FIND_NICKNAME);
    return 1;
}

public OnQueryReceived(playerid, threadid) {
    switch (threadid) {
        case E_THREAD_NONE: {
            cache_unset_active();
        }
        case E_THREAD_FIND_NICKNAME: {
            new 
                rows;

            cache_get_row_count(rows);

            if (!rows) {
                ShowPlayerDialog(playerid, DIALOG_REGISTER, DIALOG_STYLE_PASSWORD, 
                    /*-----------------------------------*/
                                "Register Server",
                    /*-----------------------------------*/
                    "Hallo user, masukin dong passwordnya\n\
                    Kalau untuk register kedalam server ya.",
                    /*-----------------------------------*/
                    "Registrasi", "Quit"
                );
            } 
            else {
                // Get login dulu, nanti baru load semua
                cache_get_value_name(0, "Nickname", PlayerData[playerid][pName]);
                cache_get_value_name(0, "Password", PlayerData[playerid][pPass]);
                cache_get_value_name(0, "Salt", PlayerData[playerid][pSalt]);

                ShowPlayerDialog(playerid, DIALOG_LOGIN, DIALOG_STYLE_PASSWORD, 
                    /*-----------------------------------*/
                                "Login Server",
                    /*-----------------------------------*/
                    "Hallo user, masukin dong passwordnya\n\
                    Kalau untuk login kedalam server ya.",
                    /*-----------------------------------*/
                    "Login", "Quit"
                );
            }
        }
        case E_THREAD_REGISTER_USER: {
            PlayerData[playerid][pId] = cache_insert_id();
            cache_unset_active();

            SavePlayerToDatabase(playerid);

            ShowPlayerDialog(playerid, E_DIALOG_LOGIN, DIALOG_STYLE_PASSWORD, 
                /*-----------------------------------*/
                            "Login Server",
                /*-----------------------------------*/
                "Hallo user, masukin dong passwordnya\n\
                Kalau untuk login kedalam server ya.",
                /*-----------------------------------*/
                "Login", "Quit"
            );            
        }
        case E_THREAD_LOAD_USER: {
            cache_get_value_name_float(0, "PosX", PlayerData[playerid][pPosX]);
            cache_get_value_name_float(0, "PosY", PlayerData[playerid][pPosY]);
            cache_get_value_name_float(0, "PosZ", PlayerData[playerid][pPosZ]);
            cache_get_value_name_float(0, "PosA", PlayerData[playerid][pPosA]);

            cache_get_value_name_int(0, "Interior", PlayerData[playerid][pInterior]);
            cache_get_value_name_int(0, "VirtualWorld", PlayerData[playerid][pVirtualWorld]);

            SetSpawnInfo(playerid, 0, 1, PlayerData[playerid][pPosX], PlayerData[playerid][pPosY], PlayerData[playerid][pPosZ], PlayerData[playerid][pPosA], 0, 0, 0, 0, 0, 0);
            TogglePlayerSpectating(playerid, false);
        }
    }
    return 1;
}

public OnDialogResponse(playerid, dialogid, response, listitem, inputtext[]) {
    switch (dialogid) {
        case E_DIALOG_LOGIN: {
            if (!response) return Kick(playerid);

            new 
                gen_hash[64];

            SHA256_PassHash(inputtext, PlayerData[playerid][pSalt], gen_hash, 63);

            if (!strcmp(PlayerData[playerid][pPass], gen_hash)) {
                new strQuery[64];
                
                mysql_format(sqlHandle, strQuery, sizeof strQuery, "SELECT * FROM players WHERE Username = '%e'",
                    PlayerData[playerid][pName]
                );
                mysql_tquery(sqlHandle, strQuery, #OnQueryReceived, "ii", playerid, E_THREAD_LOAD_USER);
            } 
            else {
                if (++ PlayerData[playerid][pWrongPass] >= 3) {
                    Kick(playerid);
                } else {
                    Message(playerid, -1, "Password yang anda masukkan salah (%d/3).", PlayerData[playerid][pWrongPass]);

                    ShowPlayerDialog(playerid, E_DIALOG_LOGIN, DIALOG_STYLE_PASSWORD, 
                        /*-----------------------------------*/
                                    "Login Server",
                        /*-----------------------------------*/
                        "Hallo user, masukin dong passwordnya\n\
                        Kalau untuk login kedalam server yh..",
                        /*-----------------------------------*/
                        "Login", "Quit"
                     );
                }
            }
            return 1;
        }
        case DIALOG_REGISTER: {
            if (!response) return Kick(playerid);

            new gen_hash[64];
            GenerateSalt(PlayerData[playerid][pSalt], 64);

            SHA256_PassHash(inputtext, PlayerData[playerid][pSalt], gen_hash, 64);
            format(PlayerData[playerid][pPass], 64, gen_hash);

            new strQuery[255];
            mysql_format(connHandle, strQuery, sizeof strQuery, "INSERT INTO players (Nickname, Password, Salt) VALUES ('%e', '%e', '%e')",
                ret_GetPlayerName(playerid),
                PlayerData[playerid][pPass],
                PlayerData[playerid][pSalt]
            );
            mysql_tquery(connHandle, strQuery, #OnQueryReceived, "ii", playerid, E_THREAD_CREATE_USER);
            return 1;
        }
    }
    return 0;
}

public OnPlayerSpawn(playerid) {
    PlayerData[playerid][pSpawned] = true;
    return 1;
}

SetupGamemode() {
    if (InitializeMySQL()) {
        ManualVehicleEngineAndLights();
        DisableInteriorEnterExits();

        EnableStuntBonusForAll(false);
        AllowInteriorWeapons(true);

        LimitPlayerMarkerRadius(15.0);
        SetNameTagDrawDistance(20.0);
        
        SetWorldTime(10);
        SetWeather(24);

        //DisableNameTagLOS();
        ShowPlayerMarkers(PLAYER_MARKERS_MODE_OFF);
    }
}

ResetPlayerVariable(playerid) {
    new resetData[E_PLAYER_DATA];
    PlayerData[playerid] = resetData;
    return 1;
}

// By RyDeR
GenerateSalt(salt[], len = sizeof salt) { 
    while(len--) 
        salt[len] = random(2) ? (random(26) + (random(2) ? 'a' : 'A')) : (random(10) + '0');
}
