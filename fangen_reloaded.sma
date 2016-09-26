// i prefer a rather strict and clean coding style.. ;)
#pragma semicolon 1

#include <amxmodx>
#include <amxmisc>
#include <fakemeta>
#include <fakemeta_util>
#include <hamsandwich>

// taken from cstrike module
// do not change that value unless you know what you do
#define OFFSET_AMMO_SGREN 389

#define TEAM_SPECTATOR 0
#define TEAM_T 1
#define TEAM_CT 2

#define FFADE_IN (1<<0) // Just here so we don't pass 0 into the function
#define FFADE_OUT (1<<1) // Fade out (not in)
#define FFADE_MODULATE (1<<2) // Modulate (don't blend)
#define FFADE_STAYOUT (1<<3) // ignores the duration, stays faded out until new ScreenFade message received

enum eTeams {
	team_spectator = 0,
	team_t = 1,
	team_ct = 2
}

// todo needs to be improved
#define IS_PLAYER(%1) (1 <= %1 <= 32)
#define IS_HUNTER(%1) (is_user_alive(%1) && ((gCTsAreAttackers && get_user_team(%1) == 2) || (!gCTsAreAttackers && get_user_team(%1) == 1)))
#define IS_HUNTED(%1) (is_user_alive(%1) && !((gCTsAreAttackers && get_user_team(%1) == 2) || (!gCTsAreAttackers && get_user_team(%1) == 1)))

enum eModels {
	mdl_smoke,
	mdl_gas_puff,
	mdl_gas_puff_b,
	mdl_gas_puff_r,
	mdl_gas_puff_o,
}

new gModels[eModels];

enum eCVars {
	bhop,
	godmode,
	swap_spawns,
	semiclip,
	touch_radius,
	touch_interp,
	speed_hunter,
	speed_hunted,
	speed_last_hunted,
	speed_slowdown,
	effects_jump_trails,
	effects_alt_roundend,
	effects_death,
	effects_sounds
}

new gCVarHandles[eCVars];

enum eMessages {
	msg_StatusIcon,
	msg_TeamScore,
	msg_ScoreInfo,
	msg_ScoreAttrib,
	msg_DeathMsg,
	msg_TextMsg,
	msg_SendAudio,
	msg_HostagePos,
	msg_Scenario,
	msg_HideWeapon,
	msg_Crosshair,
	msg_ClCorpse,
	msg_ScreenFade
}

new gMessages[eMessages];

new bool:gCanSwapSpawns;
new gSpawns[3][33]; //todo (testen, ob das hinhaut mit sizeof)
new gSpawnCount;
new gSpawnsSwapped = false;

new gRound = 0;
new bool:gInRound = false;
new bool:gCTsAreAttackers = true;

enum eScores {
	score_points,
	score_deaths,
	score_survived
}

new gScores[33][eScores];
new gTeamScores[3];

new bool:gSlowDown[33];

new bool:gSmokeEnabled[33];
new Float:gSmokeNextAttack[33];
new Float:gSmokeFuel[33];

new bool:gJustTeleported[33];

new gSyncMsg;

public plugin_init() {
	register_plugin("Fangen Reloaded", "0.6", "p4ddY");
	
	// cvars
	gCVarHandles[bhop] = register_cvar("fangen_bhop", "2");
	gCVarHandles[godmode] = register_cvar("fangen_godmode", "1");
	gCVarHandles[swap_spawns] = register_cvar("fangen_swap_spawns", "1");
	gCVarHandles[semiclip] = register_cvar("fangen_semiclip", "1");
	
	gCVarHandles[touch_radius] = register_cvar("fangen_touch_radius", "40.0");
	gCVarHandles[touch_interp] = register_cvar("fangen_touch_interp", "0.02");
	
	gCVarHandles[speed_hunter] = register_cvar("fangen_speed_hunter", "640.0");
	gCVarHandles[speed_hunted] = register_cvar("fangen_speed_hunted", "640.0");
	gCVarHandles[speed_last_hunted] = register_cvar("fangen_speed_last_hunted", "720.0");
	gCVarHandles[speed_slowdown] = register_cvar("fangen_speed_slowdown", "320.0");
	
	gCVarHandles[effects_jump_trails] = register_cvar("fangen_effects_jump_trails", "1");
	gCVarHandles[effects_alt_roundend] = register_cvar("fangen_effects_alt_roundend", "1");
	gCVarHandles[effects_death] = register_cvar("fangen_effects_death", "1");
	gCVarHandles[effects_sounds] = register_cvar("fangen_effects_sounds", "1");
	
	// events
	register_event("HLTV", "EventNewRound", "a", "1=0", "2=0");
	register_logevent("EventRoundStart", 2, "1=Round_Start");
	register_logevent("EventRoundEnd", 2, "1=Round_End");
	register_logevent("EventRoundDraw", 2, "1=Round_Draw");
	register_logevent("EventResetGame", 2, "1=Game_Commencing");
	register_logevent("EventResetGame", 2, "1&Restart_Round_");
	
	// messages
	gMessages[msg_StatusIcon] = get_user_msgid("StatusIcon");
	gMessages[msg_ScoreAttrib] = get_user_msgid("ScoreAttrib");
	gMessages[msg_DeathMsg] = get_user_msgid("DeathMsg");
	gMessages[msg_SendAudio] = get_user_msgid("SendAudio");
	gMessages[msg_TextMsg] = get_user_msgid("TextMsg");
	gMessages[msg_ScoreInfo] = get_user_msgid("ScoreInfo");
	gMessages[msg_TeamScore] = get_user_msgid("TeamScore");
	gMessages[msg_HostagePos] = get_user_msgid("HostagePos");
	gMessages[msg_Scenario] = get_user_msgid("Scenario");
	gMessages[msg_HideWeapon] = get_user_msgid("HideWeapon");
	gMessages[msg_Crosshair] = get_user_msgid("Crosshair");
	gMessages[msg_ClCorpse] = get_user_msgid("ClCorpse");
	gMessages[msg_ScreenFade] = get_user_msgid("ScreenFade");
	
	register_event("CurWeapon", "MsgCurWeapon", "be");
	register_message(gMessages[msg_StatusIcon], "MsgStatusIcon");
	register_message(gMessages[msg_ScoreAttrib], "MsgScoreAttrib");
	register_message(gMessages[msg_DeathMsg], "MsgDeathMsg");
	register_message(gMessages[msg_SendAudio], "MsgSendAudio");
	register_message(gMessages[msg_TextMsg], "MsgTextMsg");
	register_message(gMessages[msg_ClCorpse], "MsgClCorpse");
	
	set_msg_block(gMessages[msg_ScoreInfo], BLOCK_SET);
	set_msg_block(gMessages[msg_TeamScore], BLOCK_SET);
	set_msg_block(gMessages[msg_HostagePos] , BLOCK_SET); // hides hostage position on radars
	set_msg_block(gMessages[msg_Scenario], BLOCK_SET); // hides the hostage icon next to the round timer
	
	register_forward(FM_EmitSound, "FwdEmitSound");
	register_forward(FM_SetModel, "FwdSetModel");
	register_forward(FM_Think, "FwdThink");
	
	// i liek loads of ham!
	RegisterHam(Ham_Touch, "player", "FwdPlayerTouch", 1);
	RegisterHam(Ham_Touch, "grenade", "FwdGrenadeTouch", 1);
	RegisterHam(Ham_Spawn, "player", "FwdRespawn", 1);
	RegisterHam(Ham_Player_PreThink, "player", "FwdPlayerPreThink");
	RegisterHam(Ham_Player_PostThink, "player", "FwdPlayerPostThink");
	RegisterHam(Ham_AddPlayerItem, "player", "FwdAddPlayerItem");
	RegisterHam(Ham_Weapon_PrimaryAttack, "weapon_smokegrenade", "FwdPrimaryAttack");
	RegisterHam(Ham_Weapon_SecondaryAttack, "weapon_smokegrenade", "FwdSecondaryAttack");
	RegisterHam(Ham_TakeDamage, "player", "FwdTakeDamage");
	
	gSyncMsg = CreateHudSyncObj();
	set_task(5.0, "UpdateHUDAll", .flags = "b");
	
	// Detect spawn points
	InitSpawnPoints();
	
	// EventNewRound is not raised on the very first round
	EventNewRound();
	
	CreateTeleporter(Float:{-176.131423, 299.819854, 50.031250}, Float:{803.636169, 431.992614, 837.530395}, Float:{0.0, 1.0, 0.01});
}

public FwdSetModel(ent, const model[]) {
	if (!equal(model, "models/w_smokegrenade.mdl"))
		return FMRES_IGNORED;
	
	static classname[32];
	pev(ent, pev_classname, classname, charsmax(classname));
	if (!equal(classname, "grenade"))
		return FMRES_IGNORED;
	
	SetEntityRendering(ent);
	CreateEntityBeam(ent);
	
	return FMRES_HANDLED;
}

public plugin_cfg() {
	new cfg[128];
	get_configsdir(cfg, charsmax(cfg));
	add(cfg, charsmax(cfg), "/fangen.cfg");
	
	if (file_exists(cfg)) {
		server_exec();
		server_cmd("exec %s", cfg);
	}
}

public plugin_precache() {
	gModels[mdl_smoke] = precache_model("sprites/smoke.spr");
	gModels[mdl_gas_puff] = precache_model("sprites/gas_puff_01.spr");
	gModels[mdl_gas_puff_b] = precache_model("sprites/gas_puff_01b.spr");
	gModels[mdl_gas_puff_r] = precache_model("sprites/gas_puff_01r.spr");
	gModels[mdl_gas_puff_o] = precache_model("sprites/gas_puff_01o.spr");
	
	precache_model("sprites/e-tele1.spr");
	
	precache_sound("ambience/goal_1.wav");
	precache_sound("barney/letsmoveit.wav");
	precache_sound("barney/imwithyou.wav");
	precache_sound("barney/ba_later.wav");
	precache_sound("weapons/sg_explode.wav");
	
	precache_sound("weapons/cbar_hitbod1.wav");
	precache_sound("weapons/cbar_hitbod2.wav");
	precache_sound("weapons/cbar_hitbod3.wav");
	
	precache_sound("blowoff.wav");
	precache_sound("zonk.wav");

	// removing all objectives, we need to create a hostage outside the map.
	// otherwise round end would not be triggered, hence
	// it would be impossible for the hunted team to win the round.
	// 
	// (code adopted from Hide N Seek by Exolent)
	new hostage;
	do {
		hostage = engfunc(EngFunc_CreateNamedEntity, engfunc(EngFunc_AllocString, "hostage_entity"));
	} while (!pev_valid(hostage));
	
	engfunc(EngFunc_SetOrigin, hostage, Float:{0.0, 0.0, -55000.0});
	engfunc(EngFunc_SetSize, hostage, Float:{-1.0, -1.0, -1.0}, Float:{1.0, 1.0, 1.0});
	dllfunc(DLLFunc_Spawn, hostage);
	
	register_forward(FM_Spawn, "FwdSpawn");
}

public FwdSpawn(id) {
	static const ents[][] = {
		"func_bomb_target",
		"info_bomb_target",
		"hostage_entity",
		"monster_scientist",
		"func_hostage_rescue",
		"info_hostage_rescue",
		"info_vip_start",
		"func_vip_safetyzone",
		"func_escapezone",
		"func_buyzone",
		"armoury_entity"
	};
	
	static classname[32];
	pev(id, pev_classname, classname, charsmax(classname));
	
	static i;
	for (i = 0; i < sizeof(ents); i++) {
		if (equal(ents[i], classname)) {
			server_print("removing entity %d (%s)", id, ents[i]);
			engfunc(EngFunc_RemoveEntity, id);
		}
	}
}

// searches for spawn points and saves their entity ids
InitSpawnPoints() {
	gCanSwapSpawns = true;
	
	new count[3];
	
	new classnames[3][] = {"", "info_player_deathmatch", "info_player_start"};
	for (new i = 1; i < 3; i++) {
		new ent = 0;
		count[i] = 0;
		
		while ((ent = engfunc(EngFunc_FindEntityByString, ent, "classname", classnames[i]))) {
			if (count[i] >= sizeof(gSpawns[])) {
				gCanSwapSpawns = false;
				log_amx("[Fangen] spawnpoints");
				return;
			}
			
			gSpawns[i][count[i]] = ent;
			
			count[i]++;
		}
	}
	
	// make sure that the number of ct spawns and t spawns are equal
	if (count[TEAM_T] != count[TEAM_CT]) {
		log_amx("[Fangen] spawnpoints 2");
		gCanSwapSpawns = false;
		return;
	}
	
	gSpawnCount = count[TEAM_T];
}

// if possible, swaps spawn points
SwapSpawnPoints() {
	if (gCanSwapSpawns) {
		new Float:tempvec1[3], Float:tempvec2[3];
		
		for (new i = 0; i < gSpawnCount; i++) {
			pev(gSpawns[TEAM_CT][i], pev_origin, tempvec1);
			pev(gSpawns[TEAM_T][i], pev_origin, tempvec2);
			set_pev(gSpawns[TEAM_CT][i], pev_origin, tempvec2);
			set_pev(gSpawns[TEAM_T][i], pev_origin, tempvec1);
			
			pev(gSpawns[TEAM_CT][i], pev_angles, tempvec1);
			pev(gSpawns[TEAM_T][i], pev_angles, tempvec2);
			set_pev(gSpawns[TEAM_CT][i], pev_angles, tempvec2);
			set_pev(gSpawns[TEAM_T][i], pev_angles, tempvec1);
		}
		
		gSpawnsSwapped = !gSpawnsSwapped;
	}
}

HuntedCount() {
	static players[32], count;
	get_players(players, count, "ae", gCTsAreAttackers ? "TERRORIST" : "CT");
	return count;
}

HuntersCount() {
	static players[32], count;
	get_players(players, count, "ae", gCTsAreAttackers ? "CT" : "TERRORIST");
	return count;
}

UpdateHUD(id) {
	if (gInRound && is_user_alive(id)) {
		ClearSyncHud(id, gSyncMsg);
		
		if (IS_HUNTER(id)) {
			set_hudmessage(0, 0, 255, -1.0, 0.02, 1, 0.1, 5.0, 0.0, 0.0, 4);
			ShowSyncHudMsg(id, gSyncMsg, "You are a hunter! Catch as many players as possible!");
		}
		else if (get_pcvar_float(gCVarHandles[speed_last_hunted]) && HuntedCount() == 1 && HuntersCount() > 1) {
			set_hudmessage(255, 0, 0, -1.0, 0.02, 1, 0.1, 5.0, 0.0, 0.0, 4);
			ShowSyncHudMsg(id, gSyncMsg, "Since you are the last hunted player remaining, you were given an extra speed boost!");				
		}
		else {
			set_hudmessage(255, 0, 70, -1.0, 0.02, 1, 0.1, 5.0, 0.0, 0.0, 4);
			ShowSyncHudMsg(id, gSyncMsg, "You are hunted. Do not have yourself caught!");		
		}
	}
}

public UpdateHUDAll() {
	static players[32], count;
	
	if (gInRound) {
		get_players(players, count, "a");
		for (new i = 0; i < count; i++)
			UpdateHUD(players[i]);
	}
}

// sets a player's speed
UpdatePlayerSpeed(id) {
	if (id == 0) {
		new players[32], num;
	
		get_players(players, num, "a");
		for (new i = 0; i < num; i++) {
			if (players[i] > 0)
				UpdatePlayerSpeed(players[i]);
		}
	}
	else if(is_user_alive(id)) {
		new Float:speed;
	
		if (gSlowDown[id])
			speed = get_pcvar_float(gCVarHandles[speed_slowdown]);
		else if (IS_HUNTER(id))
			speed = get_pcvar_float(gCVarHandles[speed_hunter]);
		else if (get_pcvar_float(gCVarHandles[speed_last_hunted]) && HuntedCount() == 1 && HuntersCount() > 1) {
			speed = get_pcvar_float(gCVarHandles[speed_last_hunted]);
			UpdateHUD(id);
		}
		else
			speed = get_pcvar_float(gCVarHandles[speed_hunted]);
			
		set_pev(id, pev_maxspeed, speed);
		set_pev(id, pev_speed, speed);
		engfunc(EngFunc_SetClientMaxspeed, id, speed);
	}
}

UpdateTeamScores() {
	set_msg_block(gMessages[msg_TeamScore], BLOCK_NOT);
	
	message_begin(MSG_BROADCAST, gMessages[msg_TeamScore]);
	write_string("TERRORIST");
	write_short(gTeamScores[TEAM_T]);
	message_end();
	
	message_begin(MSG_BROADCAST, gMessages[msg_TeamScore]);
	write_string("CT");
	write_short(gTeamScores[TEAM_CT]);
	message_end();
	
	set_msg_block(gMessages[msg_TeamScore], BLOCK_SET);
}

UpdateScores(id) {
	if (id == 0) {
		new players[32], count;
		get_players(players, count);
		
		for (new i = 0; i < count; i++)
			UpdateScores(players[i]);
	}
	else if (is_user_connected(id)) {
		set_msg_block(gMessages[msg_ScoreInfo], BLOCK_NOT);
	
		message_begin(MSG_BROADCAST, gMessages[msg_ScoreInfo]);
		write_byte(id);
		write_short(gScores[id][score_points] + (gScores[id][score_survived] * 5));
		write_short(gScores[id][score_deaths]);
		write_short(0);
		write_short(get_user_team(id));
		message_end();

		set_msg_block(gMessages[msg_ScoreInfo], BLOCK_SET);
	}
}

FxSetRendering(entity, fx = kRenderFxNone, r = 255, g = 255, b = 255, render = kRenderNormal, amount = 16) {
	new Float:RenderColor[3];
	RenderColor[0] = float(r);
	RenderColor[1] = float(g);
	RenderColor[2] = float(b);

	set_pev(entity, pev_renderfx, fx);
	set_pev(entity, pev_rendercolor, RenderColor);
	set_pev(entity, pev_rendermode, render);
	set_pev(entity, pev_renderamt, float(amount));
}

FxKillBeams(id) {
	message_begin(MSG_BROADCAST, SVC_TEMPENTITY);
	write_byte(TE_KILLBEAM);
	write_short(id);
	message_end();	
}

FxBeamFollow(id, life, width, r, g, b, brightness) {
	message_begin(MSG_BROADCAST, SVC_TEMPENTITY);
	write_byte(TE_BEAMFOLLOW);
	write_short(id);
	write_short(gModels[mdl_smoke]);
	write_byte(life);
	write_byte(width);
	write_byte(r);
	write_byte(g);
	write_byte(b);
	write_byte(brightness);
	message_end();	
}

FxFireField(const Float:origin[3], radius, model, count, flags, lifetime) {
	message_begin(MSG_BROADCAST, SVC_TEMPENTITY);
	write_byte(TE_FIREFIELD);
	write_coord(floatround(origin[0]));
	write_coord(floatround(origin[1]));
	write_coord(floatround(origin[2]));
	write_short(radius); // radius
	write_short(model);
	write_byte(count); // count
	write_byte(flags);
	write_byte(lifetime); // lifetime
	message_end();
}

FxScreenFade(id, Float:duration, Float:holdtime, flags, r, g, b, a) {
	message_begin(MSG_ONE_UNRELIABLE, gMessages[msg_ScreenFade], _, id);
	write_short(floatround((1<<12) * duration));
	write_short(floatround((1<<12) * holdtime));
	write_short(flags);
	write_byte(r);
	write_byte(g);
	write_byte(b);
	write_byte(a);
	message_end();
}

FxImplosion() {
	
}

FxSendAudio(id, const sample[], pitch) {
	
}

CreateEntityBeam(id) {
	static classname[32];
	pev(id, pev_classname, classname, charsmax(classname));
	
	if (equal(classname, "grenade")) {
		FxBeamFollow(id, 5, 2, 255, 150, 0, 196);
		FxBeamFollow(id, 5, 1, 255, 0, 0, 64);
	}
	else if (equal(classname, "player") && is_user_alive(id)) {
		if (IS_HUNTER(id)) {
			FxBeamFollow(id, 15, 3, 0, 0, 255, 255);
			FxBeamFollow(id, 15, 2, 100, 0, 255, 255);
			FxBeamFollow(id, 15, 1, 255, 255, 255, 196);
		}
		else {
			FxBeamFollow(id, 15, 3, 255, 0, 0, 255);
			FxBeamFollow(id, 15, 2, 255, 0, 100, 255);
			FxBeamFollow(id, 15, 1, 255, 255, 255, 196);
		}
	}
}

SetEntityRendering(id) {
	static classname[32];
	pev(id, pev_classname, classname, charsmax(classname));
	
	if (equal(classname, "player") && is_user_alive(id)) {
		if (IS_HUNTER(id))
			FxSetRendering(id, kRenderFxGlowShell, 80, 0, 255, kRenderNormal, 16);
		else
			FxSetRendering(id, kRenderFxGlowShell, 255, 255, 255, kRenderNormal, 16);
	}
	else if (equal(classname, "grenade")) {
		FxSetRendering(id, kRenderFxGlowShell, 255, 150, 0, kRenderNormal, 16);
	}
}

public MsgStatusIcon(msg_id, msg_dest, id) {
	new sprite[16];
	get_msg_arg_string(2, sprite, charsmax(sprite));
	
	if (get_msg_arg_int(1) && (equal(sprite, "buyzone") || equal(sprite, "c4") || equal(sprite, "rescue")))
		return PLUGIN_HANDLED; // do not let the message arrive the player
	
	return PLUGIN_CONTINUE;
}

public MsgScoreAttrib(msg_id, msg_dest, id) {
	new flags = get_msg_arg_int(2);
	if (flags & (1<<1)) { // engine intends to display BOMB flag in scoreboard
		flags &= ~(1<<1);
		set_msg_arg_int(2, ARG_BYTE, flags);
	}
}

public MsgCurWeapon(id) {
	if (gInRound)
		UpdatePlayerSpeed(id);
}

public DeathMsg(killer, victim, bool:headshot, weapon[]) {
	if (IS_PLAYER(victim)) {
		gScores[victim][score_deaths]++;
		UpdateScores(victim);
		
		if (get_pcvar_num(gCVarHandles[effects_death])) {
			new Float:origin[3], Float:origin2[3];
			pev(victim, pev_origin, origin);
			pev(killer, pev_origin, origin2);
		
			set_pev(victim, pev_renderfx, kRenderFxNone);
			set_pev(victim, pev_rendermode, kRenderTransAlpha);
			set_pev(victim, pev_renderamt, 0.0);
			
			message_begin(MSG_BROADCAST, SVC_TEMPENTITY);
			write_byte(TE_TELEPORT);
			write_coord(floatround(origin[0]));
			write_coord(floatround(origin[1]));
			write_coord(floatround(origin[2]));
			message_end();
		}
		
		if (killer != victim && IS_PLAYER(killer)) {
			gScores[killer][score_points]++;
			UpdateScores(killer);

			if (get_pcvar_num(gCVarHandles[effects_death]))
				FxScreenFade(killer, 0.3, 0.0, FFADE_OUT, 0, 200, 50, 150);
		}
		
		FxKillBeams(victim);
		
		UpdatePlayerSpeed(0);
	}	
}

public MsgDeathMsg(msg_id, msg_dest, id) {
	static killer, victim, bool:headshot, weapon[32];

	killer = get_msg_arg_int(1);
	victim = get_msg_arg_int(2);
	headshot = get_msg_arg_int(1) == 1 ? true : false;
	get_msg_arg_string(4, weapon, charsmax(weapon));
	
	DeathMsg(killer, victim, headshot, weapon);
	
	return PLUGIN_CONTINUE;
}

public MsgSendAudio(msg_id, msg_dest, id) {
	static const sound_replace[2][][] = {
		{
			"%!MRAD_LETSGO",
			"%!MRAD_LOCKNLOAD",
			"%!MRAD_MOVEOUT",
			"%!MRAD_GO"
		},
		{
			"barney/letsmoveit.wav",
			"barney/imwithyou.wav",
			"barney/ba_later.wav",
			"barney/ba_later.wav"
		}
	};

	static sound[32];
	get_msg_arg_string(2, sound, charsmax(sound));
	
	if (equal(sound, "%!MRAD_ctwin") || equal(sound, "%!MRAD_terwin") || equal(sound, "%!MRAD_FIREINHOLE"))
		return PLUGIN_HANDLED;
	else if (get_pcvar_num(gCVarHandles[effects_sounds])) {
		for (new i = 0; i < sizeof(sound_replace[]); i++) {
			if (equal(sound, sound_replace[0][i])) {
				set_msg_arg_string(2, sound_replace[1][i]);
				break;
			}
		}
	}
	
	return PLUGIN_CONTINUE;
}

public MsgTextMsg(msg_id, msg_dest, id) {
	static blockmsg[][] = {
		"#CTs_Win",
		"#Terrorists_Win",
		"#Hostages_Not_Rescued",
		"#Target_Saved"
	};
	
	static msg[32];
	get_msg_arg_string(2, msg, charsmax(msg));
	
	for (new i = 0; i < sizeof(blockmsg); i++) {
		if (equal(msg, blockmsg[i]))
			return PLUGIN_HANDLED;
	}
	
	return PLUGIN_CONTINUE;
}

public MsgClCorpse(msg_id, msg_dest, id) {
	if (get_pcvar_num(gCVarHandles[effects_death]))
		return PLUGIN_HANDLED;

	return PLUGIN_CONTINUE;
}

// raised on new round event
public EventNewRound() {
	if (gRound > 0) {
		gCTsAreAttackers = !gCTsAreAttackers;
		
		if (get_pcvar_num(gCVarHandles[swap_spawns]) == 1 && gCanSwapSpawns) {
			if (gCTsAreAttackers) {
				SwapSpawnPoints();
				
				if (gSpawnsSwapped)
					client_print(0, print_chat, "[Fangen] Spawn points were swapped. You were spawned at the other team's spawn point.");
				else
					client_print(0, print_chat, "[Fangen] Spawn points were moved to their default location.");
			}
		}
		else if (gSpawnsSwapped) {
			// fangen_swap_spawns is set to 0 but spawn points are swapped
			// probably because the cvar has just been changed
			// hence we need to restore the original spawn points
			SwapSpawnPoints();
		}
	}
	
	gRound++;
}

public EventRoundStart() {
	gInRound = true;
	
	set_task(0.1, "EventRoundStart2");
}

// raised 0.1 seconds after roundstart event
public EventRoundStart2() {
	if (gInRound) // usually this should always be true
		UpdatePlayerSpeed(0);
}

public EventRoundEnd() {
	client_print(0, print_chat, "roundend");
	if (gInRound) {
		gInRound = false;
	
		new winning_team; // can either be TEAM_CT or TEAM_T
		
		new players[32], count;
		get_players(players, count, "ae", gCTsAreAttackers ? "TERRORIST" : "CT");
		if (count > 0) {
			for (new i = 0; i < count; i++) {
				gScores[players[i]][score_survived]++;
				UpdateScores(players[i]);
			}
			
			winning_team = gCTsAreAttackers ? TEAM_T : TEAM_CT;
		}
		else
			winning_team = gCTsAreAttackers ? TEAM_CT : TEAM_T;
		
		gTeamScores[winning_team]++;
		
		if (get_pcvar_num(gCVarHandles[effects_alt_roundend])) {
			new players[32], count;
			
			get_players(players, count);
			for (new i = 0; i < count; i++) {
				if (get_user_team(players[i]) == winning_team) {
					message_begin(MSG_ONE_UNRELIABLE, gMessages[msg_SendAudio], _, players[i]);
					write_byte(0);
					write_string("ambience/goal_1.wav");
					write_short(100);
					message_end();
					
					ClearSyncHud(players[i], gSyncMsg);
					set_hudmessage(0, 180, 0, -1.0, 0.35, 1, 0.1, 10.0, 0.0, 0.0, -1);
					ShowSyncHudMsg(players[i], gSyncMsg, "Congratulations, you have won the round!");
				}
				else {
					message_begin(MSG_ONE_UNRELIABLE, gMessages[msg_SendAudio], _, players[i]);
					write_byte(0);
					write_string("zonk.wav");
					write_short(100);
					message_end();
					
					ClearSyncHud(players[i], gSyncMsg);
					set_hudmessage(255, 0, 0, -1.0, 0.35, 1, 0.1, 10.0, 0.0, 0.0, -1);
					ShowSyncHudMsg(players[i], gSyncMsg, "Oh noes, you have lost the round...");					
				}
			}
		}
		else {
			message_begin(MSG_BROADCAST, gMessages[msg_SendAudio]);
			write_byte(0);
			write_string(winning_team == TEAM_CT ? "%!MRAD_ctwin" : "%!MRAD_terwin");
			write_short(100);
			message_end();
			
			message_begin(MSG_BROADCAST, gMessages[msg_TextMsg]);
			write_byte(4);
			write_string(winning_team == TEAM_CT ? "#CTs_Win" : "#Terrorists_Win");
			message_end();
		}
	}
	
	UpdateTeamScores();
}

public EventRoundDraw() {
	client_print(0, print_chat, "rounddraw");
	gInRound = false;
}

public EventResetGame() {
	// restore spawn points to their default
	if (gSpawnsSwapped)
		SwapSpawnPoints();
	
	gRound = 0;
	gInRound = false;
	gCTsAreAttackers = true; // description needed!
	
	// Reset all scores and update all players' scoreboards
	for (new i = 0; i < sizeof(gScores); i++) {
		gScores[i][score_points] = 0;
		gScores[i][score_deaths] = 0;
		gScores[i][score_survived] = 0;
	}
	
	for (new i = 0; i < sizeof(gTeamScores); i++)
		gTeamScores[i] = 0;
	
	UpdateTeamScores();
	UpdateScores(0);
}

public client_connect(id) {
	gScores[id][score_points] = 0;
	gScores[id][score_deaths] = 0;
	gScores[id][score_survived] = 0;	
}

public client_putinserver(id) {
	UpdateScores(0);
	UpdateTeamScores();
}

public FwdEmitSound(id, channel, sample[], Float:volume, Float:attenuation, flags, pitch) {
	if (!get_pcvar_num(gCVarHandles[effects_sounds]))
		return FMRES_IGNORED;
	
	if (equal(sample, "player/die1.wav"))
		engfunc(EngFunc_EmitSound, id, channel, "weapons/cbar_hitbod1.wav", volume, attenuation, flags, pitch);
	else if (equal(sample, "player/die2.wav"))
		engfunc(EngFunc_EmitSound, id, channel, "weapons/cbar_hitbod2.wav", volume, attenuation, flags, pitch);
	else if (equal(sample, "player/die3.wav"))
		engfunc(EngFunc_EmitSound, id, channel, "weapons/cbar_hitbod3.wav", volume, attenuation, flags, pitch);
	else if (equal(sample, "player/death6.wav"))
		engfunc(EngFunc_EmitSound, id, channel, "weapons/cbar_hitbod1.wav", volume, attenuation, flags, pitch);
	else
		return FMRES_IGNORED;
	
	return FMRES_SUPERCEDE;
}

// by default there should not be any weapons that a player could buy or pick up
// though if - for instance due to another amxx plugin - a player is given a weapon
// this forward is raised and all weapons other than weapon_knife will be removed
public FwdAddPlayerItem(id, ent) {
	static class[32];
	pev(ent, pev_classname, class, charsmax(class));
	
	// restrict all weapons except knife
	if (!(equal(class, "weapon_knife") || equal(class, "weapon_smokegrenade"))) {
		ExecuteHamB(Ham_Item_Kill, ent);
		return HAM_SUPERCEDE;
	}

	return HAM_HANDLED;
}

// raised whenever the engine spawns a player (even though he/she might be dead)
// hence we've got to make sure the player is alive
public FwdRespawn(id) {
	if (!is_user_alive(id))
		return HAM_IGNORED;
	
	gSlowDown[id] = false;
	gSmokeEnabled[id] = false;
	gSmokeFuel[id] = 100.0;
	
	gJustTeleported[id] = false;
	
	// executing client commands is one of the worst things that you can do with pawn...
	// unfortunately there's no way around
	// setting those 3 variables is necessary, otherwise players would be too slow
	client_cmd(id, "cl_forwardspeed 9999");
	client_cmd(id, "cl_sidespeed 9999");
	client_cmd(id, "cl_backspeed 9999");
	
	UpdateHUD(id);
	
	SetEntityRendering(id);
	
	fm_give_item(id, "weapon_smokegrenade");
	ExecuteHamB(Ham_GiveAmmo, id, 3, "SmokeGrenade", 3);
	client_cmd(id, "use weapon_knife");
	
	return HAM_HANDLED;
}

// handles incoming damage
public FwdTakeDamage(id, idinflictor, idattacker, Float:damage, damagebits) {
	static god;
	
	// the entitiy with id 0 is the world entity
	// taking damage by the world entity means falling damage
	god = get_pcvar_num(gCVarHandles[godmode]);
	if (god > 1 || (god > 0 && (idattacker == 0 || is_user_alive(idattacker))))
		return HAM_SUPERCEDE;
	
	return HAM_IGNORED;
}

public FwdPlayerPreThink(id) {
	static flags, oldflags[33] = {0, ...};
	static movetype, oldmovetype[33] = {0, ...};
	static Float:origin[3], Float:velocity[3];
	
	// todo
	if (!is_user_alive(id)) {
		if (oldflags[id] != 0)
			oldflags[id] = 0;
		
		if (oldmovetype[id] != 0)
			oldmovetype[id] = 0;
	
		return HAM_IGNORED;
	}
	
	pev(id, pev_origin, origin);
	pev(id, pev_velocity, velocity);
	
	if (pev(id, pev_body) == 1.0)
		set_pev(id, pev_body, 0.0);
	
	// avoid slowdowns after jumping, hence bunny hopping is possible
	if (get_pcvar_num(gCVarHandles[bhop]) > 0)
		set_pev(id, pev_fuser2, 0.0);
	
	if (get_pcvar_num(gCVarHandles[semiclip]) || pev(id, pev_solid) != SOLID_SLIDEBOX)
		set_pev(id, pev_solid, SOLID_SLIDEBOX);
	
	if (IS_HUNTER(id)) {
		static Float:predicted[3], Float:interp, Float:radius;
		
		radius = get_pcvar_float(gCVarHandles[touch_radius]);
		if (radius > 0.0) {
			interp = get_pcvar_float(gCVarHandles[touch_interp]);
			
			predicted[0] = origin[0] + (interp * velocity[0]);
			predicted[1] = origin[1] + (interp * velocity[1]);
			predicted[2] = origin[2] + (interp * velocity[2]);
			
			static ent;
			while ((ent = engfunc(EngFunc_FindEntityInSphere, ent, predicted, radius))) {
				if (id != ent) {
					static class[32];
					pev(ent, pev_classname, class, charsmax(class));
					
					if (equal(class, "player") && is_user_alive(ent) && !gJustTeleported[ent])
						FwdPlayerTouch(id, ent);
				}
			}
		}
	}
	
	flags = pev(id, pev_flags);
	movetype = pev(id, pev_movetype);
	
	if (gInRound && !gSmokeEnabled[id] && get_pcvar_num(gCVarHandles[effects_jump_trails])) {
		if ((flags & FL_ONGROUND && !(oldflags[id] & FL_ONGROUND))
		|| (movetype == MOVETYPE_FLY && oldmovetype[id] != MOVETYPE_FLY)) {
			FxKillBeams(id);
		}
		else if (oldflags[id] & FL_ONGROUND && !(flags & FL_ONGROUND) && movetype != MOVETYPE_FLY
		      || (movetype != MOVETYPE_FLY && oldmovetype[id] == MOVETYPE_FLY)) {
			CreateEntityBeam(id);
		}
	}
	
	if (gSmokeEnabled[id]) {
		if (gSmokeNextAttack[id] <= get_gametime()) {
			gSmokeNextAttack[id] = get_gametime() + 0.05;
			
			gSmokeFuel[id] -= 3;
			if (gSmokeFuel[id] < 0.0) {
				gSmokeFuel[id] = 100.0;
				gSmokeEnabled[id] = false;
			}
			
			for (new i = 0; i < 3; i++)
				origin[i] -= 0.15 * velocity[i];
			
			FxFireField(origin, 80, gModels[mdl_gas_puff_b], 8,
			              TEFIRE_FLAG_ALPHA | TEFIRE_FLAG_SOMEFLOAT, 15);
		}
	}
	
	oldflags[id] = flags;
	oldmovetype[id] = movetype;
	
	return HAM_HANDLED;
}

public FwdPlayerPostThink(id) {
	static Float:velocity[3];
	
	// enables auto hopping
	// (the user simply needs to hold down the jump button in order to do a bunny hop)
	if (get_pcvar_num(gCVarHandles[bhop]) > 1 && pev(id, pev_flags) & FL_ONGROUND && pev(id, pev_button) & IN_JUMP) {
		pev(id, pev_velocity, velocity);
		velocity[2] = 250.0;
		set_pev(id, pev_velocity, velocity);
		set_pev(id, pev_gaitsequence, 6);
	}
	
	if (get_pcvar_num(gCVarHandles[semiclip])) {
		set_pev(id, pev_solid, SOLID_NOT);
	}
}

public FwdPlayerTouch(id, other) {
	if (gInRound && is_user_alive(id) && is_user_alive(other) && IS_HUNTER(id) && IS_HUNTED(other)) {
		set_msg_block(gMessages[msg_DeathMsg], BLOCK_ONCE);
		dllfunc(DLLFunc_ClientKill, other);
		
		message_begin(MSG_BROADCAST, gMessages[msg_DeathMsg]);
		write_byte(id);
		write_byte(other);
		write_byte(0);
		write_string("his hands");
		message_end();
		
		DeathMsg(id, other, false, "his hands");
	}
}

public FwdPrimaryAttack(id) {
	static player;
	player = pev(id, pev_owner);
	
	if (IS_HUNTED(player)) {
		if (gInRound && !gSmokeEnabled[player] && gSmokeFuel[player] == 100.0) {
			gSmokeEnabled[player] = true;
			gSmokeNextAttack[player] = get_gametime();
			
			engfunc(EngFunc_EmitSound, player, CHAN_AUTO, "blowoff.wav", 1.0, 0.8, 0, 100);
			FxScreenFade(player, 1.0, 0.0, FFADE_OUT, 0, 0, 255, 100);
			
			FxKillBeams(player);
			
			new newammo = get_pdata_int(player, OFFSET_AMMO_SGREN) - 1;
			set_pdata_int(player, OFFSET_AMMO_SGREN, newammo);
			if (newammo <= 0)
				ExecuteHamB(Ham_Weapon_RetireWeapon, id);
		}
		
		return HAM_SUPERCEDE;
	}
	
	return HAM_IGNORED;
}

public FwdSecondaryAttack(id) {
	return HAM_HANDLED;
}

public FwdGrenadeTouch(id, touched) {
	if (touched == 0) {
		new Float:origin[3];
		pev(id, pev_origin, origin);
		
		// todo, CHAN_AUTO mit 1 ersetzen?!
		engfunc(EngFunc_EmitSound, id, CHAN_AUTO, "weapons/sg_explode.wav", 1.0, 0.8, 0, 100);
		
		// todo (credits xpaw)
		set_pev(id, pev_origin, Float:{9999.0, 9999.0, 9999.0});
		set_pev(id, pev_flags, FL_KILLME);
		
		FxFireField(origin, 100, gModels[mdl_gas_puff_o], 100,
		              TEFIRE_FLAG_ALPHA | TEFIRE_FLAG_ALLFLOAT, 15);
		
		new ent = 0;
		while ((ent = engfunc(EngFunc_FindEntityInSphere, ent, origin, 200.0))) {
			if (IS_PLAYER(ent) && is_user_alive(ent) && IS_HUNTED(ent)) {
				gSlowDown[ent] = true;
				UpdatePlayerSpeed(ent);
				
				new Float:velocity[3], Float:m;
				pev(ent, pev_velocity, velocity);
				
				m = get_pcvar_float(gCVarHandles[speed_slowdown])
				  / get_pcvar_float(gCVarHandles[speed_hunted]);
				for (new i = 0; i < 3; i++)
					velocity[i] *= m;
				
				set_pev(ent, pev_velocity, velocity);
				
				FxScreenFade(ent, 0.5, 3.0, FFADE_OUT, 255, 150, 0, 150);
				FxSetRendering(ent, kRenderFxGlowShell, 255, 150, 0, kRenderNormal, 16);
				
				new params[1];
				params[0] = ent;
				set_task(3.0, "StopSlowDown", _, params, sizeof(params));
			}
		}
	}
}

public StopSlowDown(params[], id) {
	gSlowDown[params[0]] = false;
	UpdatePlayerSpeed(params[0]);
	SetEntityRendering(params[0]);
}

public CreateTeleporter(const Float:origin[3], const Float:destiny[3], const Float:direction[3]) {
	new ent = engfunc(EngFunc_CreateNamedEntity, engfunc(EngFunc_AllocString, "info_target"));
	if (!ent)
		return 0;
	
	set_pev(ent, pev_classname, "fangen_teleporter");
	engfunc(EngFunc_SetModel, ent, "sprites/e-tele1.spr");
	
	dllfunc(DLLFunc_Spawn, ent);
	
	set_pev(ent, pev_movetype, MOVETYPE_NONE);
	set_pev(ent, pev_solid, SOLID_NOT);
	set_pev(ent, pev_rendermode, kRenderTransAdd);
	set_pev(ent, pev_renderamt, 255.0);
	set_pev(ent, pev_vuser1, direction);
	set_pev(ent, pev_vuser2, destiny);
	
	engfunc(EngFunc_SetOrigin, ent, origin);
	
	// make the entity think
	set_pev(ent, pev_nextthink, get_gametime());
	
	return ent;
}

public FwdThink(id) {
	static classname[32];
	
	pev(id, pev_classname, classname, charsmax(classname));
	if (!equal(classname, "fangen_teleporter"))
		return FMRES_IGNORED;
	
	static Float:origin[3];
	pev(id, pev_origin, origin);
	
	static ent;
	while ((ent = engfunc(EngFunc_FindEntityInSphere, ent, origin, 32.0))) {
		if (id == ent)
			continue;
		
		new Float:direction[3], destiny[3];
		pev(id, pev_vuser1, direction);
		pev(id, pev_vuser2, destiny);
		
		new Float:velocity[3], Float:speed;
		pev(ent, pev_velocity, velocity);
		speed = floatsqroot(velocity[0] * velocity[0] + velocity[1] * velocity[1] + velocity[2] * velocity[2]);
		
		velocity[0] = direction[0] * speed;
		velocity[1] = direction[1] * speed;
		velocity[2] = direction[2] * speed;
		
		FxKillBeams(ent);
		
		set_pev(ent, pev_origin, destiny);
		set_pev(ent, pev_velocity, velocity);
		
		new Float:angles[3];
		vector_to_angle(direction, angles);
		set_pev(ent, pev_fixangle, 1.0);
		set_pev(ent, pev_angles, angles);
		
		if (!(pev(ent, pev_flags) & FL_ONGROUND) && pev(ent, pev_movetype) != MOVETYPE_FLY)
			CreateEntityBeam(ent);
		
		if (IS_PLAYER(ent)) {
			gJustTeleported[ent] = true;
			
			new params[1];
			params[0] = ent;
			set_task(2.0, "ResetTeleported", _, params, 1);
			
			FxSetRendering(ent, kRenderFxNone, .render = kRenderTransAlpha, .amount = 85);
			FxScreenFade(ent, 0.3, 0.0, FFADE_OUT, 0, 255, 0, 150);
		}
	}
	
	new Float:curframe;
	pev(id, pev_frame, curframe);
	curframe = curframe >= 25.0 ? 1.0 : curframe + 1.0;
	set_pev(id, pev_frame, curframe);
	
	set_pev(id, pev_nextthink, get_gametime() + 0.05);
	
	return FMRES_HANDLED;
}

public ResetTeleported(params[]) {
	gJustTeleported[params[0]] = false;
	SetEntityRendering(params[0]);
}

