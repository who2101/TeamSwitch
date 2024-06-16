#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <multicolors>

#undef REQUIRE_PLUGIN
#include <adminmenu>

#undef REQUIRE_EXTENSIONS
#include <cstrike>
#define REQUIRE_EXTENSIONS


// Team indices
#define TEAM_1    2
#define TEAM_2    3
#define TEAM_SPEC 1

#define TEAMSWITCH_ADMINFLAG  ADMFLAG_KICK
#define TEAMSWITCH_ARRAY_SIZE 64

public Plugin myinfo = {
	name = "TeamSwitch", 
	author = "MistaGee", 
	description = "switch people to the other team now, at round end, on death"
};

Handle hAdminMenu = INVALID_HANDLE;
bool onRoundEndPossible = false, cstrikeExtAvail = false, switchOnRoundEnd[TEAMSWITCH_ARRAY_SIZE], switchOnDeath[TEAMSWITCH_ARRAY_SIZE];
char teamName1[2], teamName2[3];

enum TeamSwitchEvent {
	TeamSwitchEvent_Immediately = 0, 
	TeamSwitchEvent_OnDeath = 1, 
	TeamSwitchEvent_OnRoundEnd = 2, 
	TeamSwitchEvent_ToSpec = 3
};

public void OnPluginStart() {
	RegAdminCmd("teamswitch", Command_SwitchImmed, TEAMSWITCH_ADMINFLAG);
	RegAdminCmd("teamswitch_death", Command_SwitchDeath, TEAMSWITCH_ADMINFLAG);
	RegAdminCmd("teamswitch_roundend", Command_SwitchRend, TEAMSWITCH_ADMINFLAG);
	RegAdminCmd("teamswitch_spec", Command_SwitchSpec, TEAMSWITCH_ADMINFLAG);
	
	HookEvent("player_death", Event_PlayerDeath);
	
	// Hook game specific round end events - if none found, round end is not shown in menu
	char theFolder[40];
	GetGameFolderName(theFolder, sizeof(theFolder));
	
	PrintToServer("[TS] Hooking round end events for game: %s", theFolder);
	
	if (StrEqual(theFolder, "dod")) {
		HookEvent("dod_round_win", Event_RoundEnd, EventHookMode_PostNoCopy);
		onRoundEndPossible = true;
	}
	else if (StrEqual(theFolder, "tf")) {
		HookEvent("teamplay_round_win", Event_RoundEnd, EventHookMode_PostNoCopy);
		HookEvent("teamplay_round_stalemate", Event_RoundEnd, EventHookMode_PostNoCopy);
		onRoundEndPossible = true;
	}
	else if (StrEqual(theFolder, "cstrike")) {
		HookEvent("round_end", Event_RoundEnd, EventHookMode_PostNoCopy);
		onRoundEndPossible = true;
	}
	
	TopMenu topmenu;
	if (LibraryExists("adminmenu") && ((topmenu = GetAdminTopMenu()) != INVALID_HANDLE)) {
		OnAdminMenuReady(topmenu);
	}
	
	// Check for cstrike extension - if available, CS_SwitchTeam is used
	cstrikeExtAvail = (GetExtensionFileStatus("game.cstrike.ext") == 1);
	
	LoadTranslations("common.phrases");
	LoadTranslations("teamswitch.phrases");
	
}

public void OnMapStart() {
	GetTeamName(2, teamName1, sizeof(teamName1));
	GetTeamName(3, teamName2, sizeof(teamName2));
	
	PrintToServer(
		"[TS] Team Names: %s %s - OnRoundEnd available: %s", 
		teamName1, teamName2, 
		(onRoundEndPossible ? "yes" : "no")
		);
}

public Action Command_SwitchImmed(int client, int args) {
	if (args != 1) {
		ReplyToCommand(client, "Usage: teamswitch_immed <name> - Switch player to opposite team immediately");
		return Plugin_Handled;
	}
	
	// Try to find a target player
	char targetArg[50];
	GetCmdArg(1, targetArg, sizeof(targetArg));
	
	int target = FindTarget(client, targetArg);
	
	if (target != -1) {
		char target_name[50];
		GetClientName(target, target_name, sizeof(target_name));
		PerformSwitch(target);
		
		CPrintToChatAll("%t %s %t", "ts admin switch", target_name, "ts opposite team");
	}
	
	return Plugin_Handled;
}

public Action Command_SwitchDeath(int client, int args) {
	if (args != 1) {
		ReplyToCommand(client, "Usage: teamswitch_death <name> - Switch player to opposite team when they die");
		return Plugin_Handled;
	}
	
	// Try to find a target player
	char targetArg[50];
	GetCmdArg(1, targetArg, sizeof(targetArg));
	
	int target = FindTarget(client, targetArg);
	if (target != -1) {
		char target_name[50];
		switchOnDeath[target] = !switchOnDeath[target];
		GetClientName(target, target_name, sizeof(target_name));
		CPrintToChatAll("%s %t %s %t", target_name, "ts will", (switchOnRoundEnd[target] ? "" : "%t", "ts not"), "ts apposite team on death");
	}
	
	return Plugin_Handled;
}

public Action Command_SwitchRend(int client, int args) {
	if (args != 1) {
		ReplyToCommand(client, "Usage: teamswitch_roundend <name> - Switch player to opposite team when the round ends");
		return Plugin_Handled;
	}
	
	if (!onRoundEndPossible) {
		ReplyToCommand(client, "Switching on round end is not possible in this mod.");
		return Plugin_Handled;
	}
	
	// Try to find a target player
	char targetArg[50];
	GetCmdArg(1, targetArg, sizeof(targetArg));
	
	int target = FindTarget(client, targetArg);
	
	if (target != -1) {
		char target_name[50];
		switchOnRoundEnd[target] = !switchOnRoundEnd[target];
		GetClientName(target, target_name, sizeof(target_name));
		CPrintToChatAll("%s %t %s %t", target_name, "ts will", (switchOnRoundEnd[target] ? "" : "%t", "ts not"), "ts apposite team on round end");
	}
	
	return Plugin_Handled;
}

public Action Command_SwitchSpec(int client, int args) {
	if (args != 1) {
		ReplyToCommand(client, "Usage: teamswitch_spec <name> - Switch player to spectators immediately");
		return Plugin_Handled;
	}
	
	// Try to find a target player
	char targetArg[50];
	GetCmdArg(1, targetArg, sizeof(targetArg));
	
	int target = FindTarget(client, targetArg);
	if (target != -1) {
		char target_name[50];
		GetClientName(target, target_name, sizeof(target_name));
		PerformSwitch(target, true);
		CPrintToChatAll("%t %s %t", "ts admin switch", target_name, "ts opposite team");
	}
	
	return Plugin_Handled;
}

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast) {
	int victim = GetClientOfUserId(GetEventInt(event, "userid"));
	
	if (victim > 0 && IsClientInGame(victim) && switchOnDeath[victim]) {
		PerformTimedSwitch(victim);
		switchOnDeath[victim] = false;
	}
}

public void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast) {
	if (!onRoundEndPossible)
		return;
	
	for (int i = 0; i < TEAMSWITCH_ARRAY_SIZE; i++) {
		if (switchOnRoundEnd[i]) {
			PerformTimedSwitch(i);
			switchOnRoundEnd[i] = false;
		}
	}
}


/******************************************************************************************
 *                                   ADMIN MENU HANDLERS                                  *
 ******************************************************************************************/

public void OnLibraryRemoved(const char[] name) {
	if (StrEqual(name, "adminmenu")) {
		hAdminMenu = INVALID_HANDLE;
	}
}

public void OnAdminMenuReady(Handle topmenu) {
	// Block us from being called twice
	if (topmenu == hAdminMenu) {
		return;
	}
	hAdminMenu = topmenu;
	
	// Now add stuff to the menu: My very own category *yay*
	TopMenuObject menu_category = AddToTopMenu(
		hAdminMenu,  // Menu
		"ts_commands",  // Name
		TopMenuObject_Category,  // Type
		Handle_Category,  // Callback
		INVALID_TOPMENUOBJECT // Parent
		);
	
	if (menu_category == INVALID_TOPMENUOBJECT) {
		// Error... lame...
		return;
	}
	
	// Now add items to it
	AddToTopMenu(
		hAdminMenu,  // Menu
		"ts_immed",  // Name
		TopMenuObject_Item,  // Type
		Handle_ModeImmed,  // Callback
		menu_category,  // Parent
		"ts_immed",  // cmdName
		TEAMSWITCH_ADMINFLAG // Admin flag
		);
	
	AddToTopMenu(
		hAdminMenu,  // Menu
		"ts_death",  // Name
		TopMenuObject_Item,  // Type
		Handle_ModeDeath,  // Callback
		menu_category,  // Parent
		"ts_death",  // cmdName
		TEAMSWITCH_ADMINFLAG // Admin flag
		);
	
	if (onRoundEndPossible) {
		AddToTopMenu(
			hAdminMenu,  // Menu
			"ts_rend",  // Name
			TopMenuObject_Item,  // Type
			Handle_ModeRend,  // Callback
			menu_category,  // Parent
			"ts_rend",  // cmdName
			TEAMSWITCH_ADMINFLAG // Admin flag
			);
	}
	
	AddToTopMenu(
		hAdminMenu,  // Menu
		"ts_spec",  // Name
		TopMenuObject_Item,  // Type
		Handle_ModeSpec,  // Callback
		menu_category,  // Parent
		"ts_spec",  // cmdName
		TEAMSWITCH_ADMINFLAG // Admin flag
		);
	
}

public int Handle_Category(TopMenu topmenu, TopMenuAction action, TopMenuObject topobj_id, int param, char[] buffer, int maxlength) {
	switch (action) {
		case TopMenuAction_DisplayTitle:
		Format(buffer, maxlength, "%T", "ts when", param);
		case TopMenuAction_DisplayOption:
		Format(buffer, maxlength, "%T", "ts commands", param);
	}
	
	return 0;
}

public void Handle_ModeImmed(TopMenu topmenu, TopMenuAction action, TopMenuObject topobj_id, int param, char[] buffer, int maxlength) {
	if (action == TopMenuAction_DisplayOption) {
		Format(buffer, maxlength, "%t", "ts immediately", param);
	}
	else if (action == TopMenuAction_SelectOption) {
		ShowPlayerSelectionMenu(param, TeamSwitchEvent_Immediately);
	}
}

public void Handle_ModeDeath(TopMenu topmenu, TopMenuAction action, TopMenuObject topobj_id, int param, char[] buffer, int maxlength) {
	if (action == TopMenuAction_DisplayOption) {
		Format(buffer, maxlength, "%T", "ts on death", param);
	}
	else if (action == TopMenuAction_SelectOption) {
		ShowPlayerSelectionMenu(param, TeamSwitchEvent_OnDeath);
	}
}

public void Handle_ModeRend(TopMenu topmenu, TopMenuAction action, TopMenuObject topobj_id, int param, char[] buffer, int maxlength) {
	if (action == TopMenuAction_DisplayOption) {
		Format(buffer, maxlength, "%T", "ts on round end", param);
	}
	else if (action == TopMenuAction_SelectOption) {
		ShowPlayerSelectionMenu(param, TeamSwitchEvent_OnRoundEnd);
	}
}

public void Handle_ModeSpec(TopMenu topmenu, TopMenuAction action, TopMenuObject topobj_id, int param, char[] buffer, int maxlength) {
	if (action == TopMenuAction_DisplayOption) {
		Format(buffer, maxlength, "%T", "ts to spec", param);
	}
	else if (action == TopMenuAction_SelectOption) {
		ShowPlayerSelectionMenu(param, TeamSwitchEvent_ToSpec);
	}
}


/******************************************************************************************
 *                           PLAYER SELECTION MENU HANDLERS                               *
 ******************************************************************************************/

void ShowPlayerSelectionMenu(int client, TeamSwitchEvent event, int item = 0) {
	Menu playerMenu;
	
	// Create Menu with the correct Handler, so I don't have to store which player chose
	// which action...
	switch (event) {
		case TeamSwitchEvent_Immediately:
		playerMenu = new Menu(Handle_SwitchImmed);
		case TeamSwitchEvent_OnDeath:
		playerMenu = new Menu(Handle_SwitchDeath);
		case TeamSwitchEvent_OnRoundEnd:
		playerMenu = new Menu(Handle_SwitchRend);
		case TeamSwitchEvent_ToSpec:
		playerMenu = new Menu(Handle_SwitchSpec);
	}
	
	SetMenuTitle(playerMenu, "%T", "ts choose player", client);
	SetMenuExitButton(playerMenu, true);
	SetMenuExitBackButton(playerMenu, true);
	
	// Now add players to it
	// I'm aware there is a function AddTargetsToMenu in the SourceMod API, but I don't
	// use that one because it does not display the team the clients are in.
	int cTeam = 0;
	
	char cName[45], buffer[50], cBuffer[5];
	
	for (int i = 1; i <= MaxClients; i++) {
		if (IsClientInGame(i)) {
			cTeam = GetClientTeam(i);
			if (cTeam < 2)
				continue;
			
			GetClientName(i, cName, sizeof(cName));
			
			switch (event) {
				case TeamSwitchEvent_Immediately, 
				TeamSwitchEvent_ToSpec:
				Format(buffer, sizeof(buffer), 
					"[%s] %s", 
					(cTeam == 2 ? teamName1 : teamName2), 
					cName
					);
				case TeamSwitchEvent_OnDeath:
				Format(buffer, sizeof(buffer), 
					"[%s] [%s] %s", 
					(switchOnDeath[i] ? 'x' : ' '), 
					(cTeam == 2 ? teamName1 : teamName2), 
					cName
					);
				case TeamSwitchEvent_OnRoundEnd:
				Format(buffer, sizeof(buffer), 
					"[%s] [%s] %s", 
					(switchOnRoundEnd[i] ? 'x' : ' '), 
					(cTeam == 2 ? teamName1 : teamName2), 
					cName
					);
			}
			
			IntToString(i, cBuffer, sizeof(cBuffer));
			
			AddMenuItem(playerMenu, cBuffer, buffer);
		}
	}
	
	// Send the menu to our admin
	if (item == 0)
		DisplayMenu(playerMenu, client, 30);
	else DisplayMenuAtItem(playerMenu, client, item - 1, 30);
}

public int Handle_SwitchImmed(Menu playerMenu, MenuAction action, int client, int target) {
	Handle_Switch(TeamSwitchEvent_Immediately, playerMenu, action, client, target);
	
	return 0;
}

public int Handle_SwitchDeath(Menu playerMenu, MenuAction action, int client, int target) {
	Handle_Switch(TeamSwitchEvent_OnDeath, playerMenu, action, client, target);
	
	return 0;
}

public int Handle_SwitchRend(Menu playerMenu, MenuAction action, int client, int target) {
	Handle_Switch(TeamSwitchEvent_OnRoundEnd, playerMenu, action, client, target);
	
	return 0;
}

public int Handle_SwitchSpec(Menu playerMenu, MenuAction action, int client, int target) {
	Handle_Switch(TeamSwitchEvent_ToSpec, playerMenu, action, client, target);
	
	return 0;
}

void Handle_Switch(TeamSwitchEvent event, Menu playerMenu, MenuAction action, int client, int param) {
	switch (action) {
		case MenuAction_Select: {
			char info[5];
			GetMenuItem(playerMenu, param, info, sizeof(info));
			int target = StringToInt(info);
			
			switch (event) {
				case TeamSwitchEvent_Immediately:
				PerformSwitch(target);
				case TeamSwitchEvent_OnDeath: {
					// If alive: player must be listed in OnDeath array
					if (IsPlayerAlive(target)) {
						// If alive, toggle status
						switchOnDeath[target] = !switchOnDeath[target];
					}
					else // Switch right away
						PerformSwitch(target);
				}
				case TeamSwitchEvent_OnRoundEnd: {
					// Toggle status
					switchOnRoundEnd[target] = !switchOnRoundEnd[target];
				}
				case TeamSwitchEvent_ToSpec:
				PerformSwitch(target, true);
			}
			// Now display the menu again
			ShowPlayerSelectionMenu(client, event, target);
		}
		
		case MenuAction_Cancel:
		// param gives us the reason why the menu was cancelled
		if (param == MenuCancel_ExitBack)
			RedisplayAdminMenu(hAdminMenu, client);
		
		case MenuAction_End:
		CloseHandle(playerMenu);
	}
}


void PerformTimedSwitch(int client) {
	CreateTimer(0.5, Timer_TeamSwitch, client);
}

public Action Timer_TeamSwitch(Handle timer, int client) {
	if (IsClientInGame(client))
		PerformSwitch(client);
	return Plugin_Stop;
}

void PerformSwitch(int client, bool toSpec = false) {
	int cTeam = GetClientTeam(client), 
	toTeam = (toSpec ? TEAM_SPEC : TEAM_1 + TEAM_2 - cTeam);
	
	if (cstrikeExtAvail && !toSpec)
		CS_SwitchTeam(client, toTeam);
	else ChangeClientTeam(client, toTeam);
	
	char plName[40];
	GetClientName(client, plName, sizeof(plName));
	
	CPrintToChatAll("%t", "ts switch by admin", plName);
}