#pragma semicolon 1

#include <sourcemod>
#include <socket>

#define CVAR_ARRAY_NAME 0
#define CVAR_ARRAY_MINVALUE 1
#define CVAR_ARRAY_MAXVALUE 2

#define CLIENTCVAR_ARRAY_NAME 0
#define CLIENTCVAR_ARRAY_CLIENT_VALUE 1

public Plugin:myinfo =
{
    name = "ozfortress detective",
    author = "bladez",
    description = "detects",
    version = "0.2",
    url = "http://ozfortress.com"
};

new bool:late_loaded;
new bool:b_player_warned[MAXPLAYERS+1] = {false, ...};

new Handle:h_cvars = INVALID_HANDLE;
new Handle:h_cvar_index = INVALID_HANDLE;
new Handle:h_client_cvars[MAXPLAYERS+1] = {INVALID_HANDLE, ...};
new Handle:ipgn_botip = INVALID_HANDLE;
new Handle:ipgn_botport = INVALID_HANDLE;

public APLRes:AskPluginLoad2(Handle:myself, bool:late, String:error[], err_max)
{
    late_loaded = late;
    return APLRes_Success;
}

public OnPluginStart()
{
    h_cvars = CreateArray(64);
    h_cvar_index = CreateTrie();

    addCVar("fov_desired", 80.0, 90.0);
    addCVar("r_drawothermodels", 0.0, 2.0);
    addCVar("mat_picmip", -1.0, 4.0);
    addCVar("r_lod", -1.0, 2.0);
    addCVar("r_rootlod", 0.0, 2.0);
    addCVar("r_drawviewmodel", 0.0, 1.0);

    CreateTimer(60.0, getClientCVarTimer, _, TIMER_REPEAT);

    RegConsoleCmd("gogogadget", gogoGadgetDetective);

    if ((ipgn_botip = FindConVar("mr_ipgnbotip")) == INVALID_HANDLE)
    {
        ipgn_botip = CreateConVar("mr_ipgnbotip", "210.50.4.5", "IP address for iPGN booking bot", FCVAR_PROTECTED);
    }
    if ((ipgn_botport = FindConVar("mr_ipgnbotport")) == INVALID_HANDLE)
    {
        ipgn_botport = CreateConVar("mr_ipgnbotport", "6002", "Port for iPGN booking bot", FCVAR_PROTECTED);
    }
}

public OnPluginEnd()
{
    for (new i = 1; i <= MaxClients; i++)
    {
        if (IsClientConnected(i) && !IsFakeClient(i))
        {
            CloseHandle(h_client_cvars[i]);
        }
    }
}

public OnClientDisconnect(client)
{
    CloseHandle(h_client_cvars[client]);
    b_player_warned[client] = false;
}

public Action:getClientCVarTimer(Handle:timer, any:data)
{
    checkCVars(); 
}

public clientCVarCallback(QueryCookie:cookie, client, ConVarQueryResult:result, const String:cvar_name[], const String:cvar_value[])
{
    decl String:client_name[64], String:client_auth[64], String:client_ip[64], String:client_report[256];
    GetClientName(client, client_name, sizeof(client_name));
    GetClientAuthString(client, client_auth, sizeof(client_auth));
    GetClientIP(client, client_ip, sizeof(client_ip));

    LogMessage("%s (%s) @ %s has CVAR %s value: %s", client_name, client_auth, client_ip, cvar_name, cvar_value);

    new cvar_index;
    if (!GetTrieValue(h_cvar_index, cvar_name, cvar_index))
    {
        LogError("Couldn't find cvar in index");

        return;
    }

    new Handle:h_cvar_array = GetArrayCell(h_cvars, cvar_index), Handle:h_client_trie = h_client_cvars[client];
    new bool:b_report = false, bool:b_new_client = false;

    new Float:cvar_lower_bound = GetArrayCell(h_cvar_array, CVAR_ARRAY_MINVALUE);
    new Float:cvar_upper_bound = GetArrayCell(h_cvar_array, CVAR_ARRAY_MAXVALUE);
    new cvar_int = StringToInt(cvar_value), client_prev_value;

    if (h_client_trie == INVALID_HANDLE)
    {
        h_client_trie = CreateTrie();
        h_client_cvars[client] = h_client_trie;
    }

    if (!GetTrieValue(h_client_trie, cvar_name, client_prev_value))
    {
        b_new_client = true;
        if (!SetTrieValue(h_client_trie, cvar_name, cvar_int))
        {
            LogError("Unable to insert value into client trie for cvar %s", cvar_name);
        }
    }

    if (cvar_int > cvar_upper_bound)
    {
        //LogMessage("%s (%s) @ %s has %s ABOVE UPPER BOUND. REPORTING", client_name, client_auth, client_ip, cvar_name);
        b_report = true;
    }
    else if (cvar_int < cvar_lower_bound)
    {
        //LogMessage("%s (%s) @ %s has %s BELOW LOWER BOUND. REPORTING", client_name, client_auth, client_ip, cvar_name);
        b_report = true;
    }

    if (b_report)
    {
        LogMessage("new client: %b prev value: %d current value: %d compare: %b", b_new_client, client_prev_value, cvar_int, cvar_int != client_prev_value);
        if ((cvar_int != client_prev_value) || (b_new_client))
        {
            LogMessage("Client is new and must be reported, or has changed the CVar value for %s from %d to %d", cvar_name, client_prev_value, cvar_int);
            Format(client_report, sizeof(client_report), "CVAR_REPORT!%s!%s!%s!%s!%s", client_name, client_auth, client_ip, cvar_name, cvar_value);
            sendSocketData(client_report);

            SetTrieValue(h_client_trie, cvar_name, cvar_int); //update the trie with the new value

            b_player_warned[client] = false;
        }
        //CVAR_REPORT!NAME!ID!IP!CVAR!VALUE
        if (!b_player_warned[client])
        {
            //PrintToChat(client, "WARNING: You are using an illegal CVar value for "%s" (%s). If you continue to do so, you will be banned from future competitions", cvar_name, cvar_value);

            b_player_warned[client] = true;
        }
    }
}

public Action:gogoGadgetDetective(client, args)
{
    if (client == 0)
    {
        checkCVars();
    }
}

public onSocketConnected(Handle:socket, any:arg)
{
    decl String:msg[256];

    ResetPack(arg); //arg is a datapack containing the message to send, need to get back to the starting position
    ReadPackString(arg, msg, sizeof(msg)); //msg now contains what we want to send

    SocketSend(socket, msg);
}

public onSocketReceive(Handle:socket, String:rcvd[], const dataSize, any:arg)
{
    LogMessage("Received message %s", rcvd);
}

public onSocketDisconnect(Handle:socket, any:arg)
{
    CloseHandle(socket);
}

public onSocketSendQueueEmpty(Handle:socket, any:arg) 
{
    SocketDisconnect(socket);
    CloseHandle(socket);
}

public onSocketError(Handle:socket, const errorType, const errorNum, any:arg)
{
    LogError("SOCKET ERROR %d (errno %d)", errorType, errorNum);
    CloseHandle(socket);
}

public sendSocketData(String:msg[])
{
    new Handle:socket = SocketCreate(SOCKET_UDP, onSocketError);

    SocketSetSendqueueEmptyCallback(socket, onSocketSendQueueEmpty);

    decl String:botIP[32];
    new botPort;

    GetConVarString(ipgn_botip, botIP, sizeof(botIP));
    botPort = GetConVarInt(ipgn_botport);

    new Handle:socket_pack = CreateDataPack();
    WritePackString(socket_pack, msg);

    SocketSetArg(socket, socket_pack);

    SocketConnect(socket, onSocketConnected, onSocketReceive, onSocketDisconnect, botIP, botPort);
}

checkCVars()
{
    new Handle:h_cvar_array;
    decl String:cvar_name[64];


    for (new i = 1; i <= MaxClients; i++)
    {
        if (IsClientConnected(i) && !IsFakeClient(i))
        {
            if (h_client_cvars[i] == INVALID_HANDLE)
            {
                h_client_cvars[i] = CreateTrie();
            }

            new i_cvars = GetArraySize(h_cvars);

            for (new j = 0; j < i_cvars; j++)
            {
                h_cvar_array = GetArrayCell(h_cvars, j);

                GetArrayString(h_cvar_array, CVAR_ARRAY_NAME, cvar_name, sizeof(cvar_name));
                QueryClientConVar(i, cvar_name, clientCVarCallback, GetClientUserId(i));
            }
            
        }
    }  
}


addCVar(const String:cvar_name[], Float:cvar_minvalue, Float:cvar_maxvalue)
{
    LogMessage("Adding CVar %s to checking array", cvar_name);

    new Handle:h_cvar_array = CreateArray(64);
    PushArrayString(h_cvar_array, cvar_name);
    PushArrayCell(h_cvar_array, cvar_minvalue);
    PushArrayCell(h_cvar_array, cvar_maxvalue);

    new array_index = PushArrayCell(h_cvars, h_cvar_array);

    SetTrieValue(h_cvar_index, cvar_name, array_index);

    //LogMessage("cvar array added at index %d to global cvar array", array_index);
}