/*
 * Todo:
 *  - VGUI blocken
 *  - bei Dodge jumpanim setzen
 *  - FFADE nutzen
 *  - ScreenShake maybe usen
 * 
 * Überwachen:
 *  - oldflags_array vllt global machen
 *  - task_CVars mit den modes da
 *  - mit dem abs bei tickcount aufpassen
 */

#include <amxmodx>
#include <amxmisc>
#include <hlsdk_const>
#include <engine_const>
#include <fakemeta>
#include <cstrike>

// Konstanten
#define TIME_DODGE 500
#define TIME_DELTA_DODGE 1000
#define TIME_DELTA_SHOOT 1000
#define TIME_RESPAWN 5
#define TIME_MAKENORMAL 5.0

#define TEAM_SPEC 0
#define TEAM_T 1
#define TEAM_CT 2

#define POINTS_DEFAULT 1
#define POINTS_HEADSHOT 2

#define EFF_DODGE       (1<<0)
#define EFF_SHOOT       (1<<1)
#define EFF_SPAWN       (1<<2)
#define EFF_GORE        (1<<3)
#define EFF_GORE_SMOKE  (1<<4)
#define EFF_STEAM       (1<<5)
#define EFF_BAR         (1<<6)
#define EFF_CROSSHAIR   (1<<7)

#define FFADE_IN         0x0000 // Just here so we don't pass 0 into the function
#define FFADE_OUT        0x0001 // Fade out (not in)
#define FFADE_MODULATE   0x0002 // Modulate (don't blend)
#define FFADE_STAYOUT    0x0004 // ignores the duration, stays faded out until new ScreenFade message received

#define GAME_DM 0
#define GAME_TDM 1

#define TXT_HEADSHOT "ZOMG! Headshot by %s"

// Globale Variablen
new g_InRound = false
new g_TeamScore[3]

// Spielerspezifische Variablen
new gp_ButtonTime[33][16]
new gp_Jumps[33]
new bool:gp_InDodge[33]
new gp_LastDodge[33]
new gp_LastShot[33]
new gp_Score[33][2]
new bool:gp_BlockShoot[33]

// CVars
new varh_MaxJumps
new varh_Dodge
new varh_Speed
new varh_Comments
new varh_Zoom
new varh_Effects
new varh_Gamemode
new varh_Respawn
new varh_SpawnProt

new var_MaxJumps
new Float:var_Dodge
new Float:var_Speed
new var_Comments
new var_Zoom
new var_Effects
new var_Gamemode
new var_Respawn
new var_SpawnProt

// Models
new mdl_Smoke
new mdl_Steam
new mdl_vWeapon
new mdl_pWeapon

new mdl_gib_Flesh
new mdl_gib_Meat
new mdl_gib_Head

new mdl_blood_Drop
new mdl_blood_Spray

new g_Blood[8]
new g_BloodNum

// Messages
new msg_ScreenFade
new msg_DeathMsg
new msg_ScoreInfo
new msg_TeamScore

// Misc
new sync_Comment
new sync_Timer

// copied from CSDM
new g_Aliases[34][] = {"usp","glock","deagle","p228","elites","fn57","m3","xm1014","mp5","tmp","p90","mac10","ump45","ak47","galil","famas","sg552","m4a1","aug","scout","awp","g3sg1","sg550","m249","vest","vesthelm","flash","hegren","sgren","defuser","nvgs","shield","primammo","secammo"} 
new g_Aliases2[34][] = {"km45","9x19mm","nighthawk","228compact","elites","fiveseven","12gauge","autoshotgun","smg","mp","c90","mac10","ump45","cv47","defender","clarion","krieg552","m4a1","bullpup","scout","magnum","d3au1","krieg550","m249","vest","vesthelm","flash","hegren","sgren","defuser","nvgs","shield","primammo","secammo"}

public plugin_init()
{
	register_plugin("InstaGibX", "0.1", "p4ddY")
	
	// Commands
	register_clcmd("buy", "cmd_Block")
	register_clcmd("buymenu", "cmd_Block")
	register_clcmd("cl_autobuy", "cmd_Block") 
	register_clcmd("cl_rebuy", "cmd_Block") 
	register_clcmd("cl_setautobuy", "cmd_Block") 
	register_clcmd("cl_setrebuy", "cmd_Block")
	register_clcmd("fullupdate", "cmd_Block")
	
	register_srvcmd("igx_spawnpoint", "cmd_SpawnPoint")
	
	// Events
	register_event("ResetHUD", "forward_ResetHUD", "be")
	register_event("CurWeapon", "forward_CurWeapon", "be")
	
	register_logevent("forward_RoundStart", 2, "0=World triggered", "1=Round_Start")
	register_logevent("forward_RoundEnd", 2, "0=World triggered", "1=Round_End")
	register_logevent("forward_RoundDraw", 2, "0=World triggered", "1=Round_Draw")
	register_logevent("forward_ResetGame", 2, "0=World triggered", "1=Game_Commencing")
	register_logevent("forward_ResetGame", 2, "1&Restart_Round_")
	
	// Forwards
	register_forward(FM_PlayerPreThink, "forward_PlayerPreThink")
	
	// CVars
	varh_MaxJumps = register_cvar("igx_maxjumps", "1")
	varh_Dodge = register_cvar("igx_dodge", "750.0")
	varh_Speed = register_cvar("igx_speed", "1.5")
	varh_Comments = register_cvar("igx_comments", "0")
	varh_Zoom = register_cvar("igx_zoom", "1")
	varh_Effects = register_cvar("igx_effects", "abcdef")
	varh_Gamemode = register_cvar("igx_mode", "1")
	varh_Respawn = register_cvar("igx_respawn", "0")
	varh_SpawnProt = register_cvar("igx_spawn_protection", "0")
	
	// Messages
	msg_ScreenFade = get_user_msgid("ScreenFade")
	msg_DeathMsg = get_user_msgid("DeathMsg")
	msg_ScoreInfo = get_user_msgid("ScoreInfo")
	msg_TeamScore = get_user_msgid("TeamScore")
	
	set_msg_block(msg_ScoreInfo, BLOCK_SET)
	set_msg_block(msg_TeamScore, BLOCK_SET)
	
	set_task(1.0, "task_CVars", _, _, _, "ab")
	set_task(1.0, "task_Respawn", _, _, _, "ab")
	
	// Misc
	sync_Comment = CreateHudSyncObj()
	sync_Timer = CreateHudSyncObj()
	
	new modname[32]
	get_modname(modname, 31)
	
	if (equali(modname, "cstrike"))
	{
		g_Blood = {190, 191, 192, 193, 194, 196, 197, 0}
		g_BloodNum = 7
	}
	else if (equali(modname, "czero"))
	{
		g_Blood = {202, 203, 204, 205, 206, 207, 208, 209}
		g_BloodNum = 8
	}
}

public plugin_cfg()
{
	server_exec()
	server_cmd("sv_maxspeed 9999")
}

public plugin_precache()
{
	mdl_Smoke = precache_model("sprites/smoke.spr")
	mdl_Steam = precache_model("sprites/steam1.spr")
	precache_sound("instagibx/fire.wav")
	precache_sound("instagibx/jump.wav")
	precache_sound("instagibx/headshot.wav")
	
	precache_model("models/instagibx/v_mg_hv.mdl")
	precache_model("models/instagibx/p_mg.mdl")
	
	mdl_vWeapon = engfunc(EngFunc_AllocString, "models/instagibx/v_mg_hv.mdl")
	mdl_pWeapon = engfunc(EngFunc_AllocString, "models/instagibx/p_mg.mdl")
	
	mdl_gib_Flesh = precache_model("models/Fleshgibs.mdl")
	mdl_gib_Meat = precache_model("models/GIB_B_Gib.mdl")
	mdl_gib_Head = precache_model("models/GIB_Skull.mdl")
	
	mdl_blood_Drop = precache_model("sprites/blood.spr")
	mdl_blood_Spray = precache_model("sprites/bloodspray.spr")
}

// Tasks
public task_CVars()
{
	static effects[32], eflen, i, oldmode
	
	var_Dodge = get_pcvar_float(varh_Dodge)
	var_Speed = get_pcvar_float(varh_Speed)
	
	var_MaxJumps = get_pcvar_num(varh_MaxJumps)
	var_Zoom = get_pcvar_num(varh_Zoom)
	var_Comments = get_pcvar_num(varh_Comments)
	var_Respawn = get_pcvar_num(varh_Respawn)
	var_SpawnProt = get_pcvar_num(varh_SpawnProt)
	
	get_pcvar_string(varh_Effects, effects, 31)
	var_Effects = 0
	eflen = strlen(effects)
	
	for (i = 0; i < eflen; i++)
	{
		switch (effects[i])
		{
			case 'a': var_Effects |= EFF_DODGE
			case 'b': var_Effects |= EFF_SHOOT
			case 'c': var_Effects |= EFF_SPAWN
			case 'd': var_Effects |= EFF_GORE
			case 'e': var_Effects |= EFF_GORE_SMOKE
			case 'f': var_Effects |= EFF_STEAM
			case 'g': var_Effects |= EFF_BAR
			case 'h': var_Effects |= EFF_CROSSHAIR
		}
	}
	
	var_Gamemode = get_pcvar_num(varh_Gamemode)
	if (var_Gamemode != oldmode)
	{
		oldmode = var_Gamemode
		
		if (var_Gamemode == 0)
			client_print(0, print_chat, "[IGX] Starting Deathmatch..")
		else
		{
			var_Gamemode = 1
			client_print(0, print_chat, "[IGX] Starting Team Deathmatch..")
		}
		
		set_cvar_num("sv_restartround", 3)
	}
}

public task_Respawn()
{
	static players[32], pCount, nextrespawn = TIME_RESPAWN, i, player, model[32]
	
	if (g_InRound && var_Respawn)
	{
		set_hudmessage(0, 0, 255, _, 0.05, 1, 0.1, 2.0, 0.1, 0.1, -1)
		ClearSyncHud(0, sync_Timer)
		
		if (nextrespawn <= 0)
			ShowSyncHudMsg(0, sync_Timer, "Next respawn: NOW")
		else
			ShowSyncHudMsg(0, sync_Timer, "Next respawn in %d seconds ...", nextrespawn)
		
		if (nextrespawn <= 0)
		{
			nextrespawn = TIME_RESPAWN + 1
			
			get_players(players, pCount, "b")
			for (i = 0, player = players[i]; i < pCount; i++, player = players[i])
			{
				pev(player, pev_model, model, 31)
				if (!equal(model, "models/player.mdl"))
				{
					// Respawne den Spieler :>
					dllfunc(DLLFunc_Spawn, player)
					
					new arr[2]
					arr[0] = player
					set_task(0.5, "task_SpawnAgain", _, arr, 1)
				}
			}
		}
		
		nextrespawn--
	}
}

public task_SpawnAgain(params[], task)
{
	if (is_user_alive(params[0]))
		dllfunc(DLLFunc_Spawn, params[0])
}

// Funktionen
public ResetVars(id)
{
	if (id == 0)
	{
		g_TeamScore = {0, 0, 0}
	}
	else
	{
		gp_Jumps[id] = 0
		gp_InDodge[id] = false
		gp_LastDodge[id] = 0
		gp_LastShot[id] = 0
		gp_Score[id] = {0, 0}
		gp_BlockShoot[id] = false
		
		for (new i = 0; i < 16; i++)
			gp_ButtonTime[id][i] = 0
	}
}

public StripWeapons(id)
{
	new ent = engfunc(EngFunc_CreateNamedEntity, engfunc(EngFunc_AllocString, "player_weaponstrip"))
	
	dllfunc(DLLFunc_Spawn, ent)
	dllfunc(DLLFunc_Use, ent, id)
	engfunc(EngFunc_RemoveEntity, ent)
}

// Von Ultimate Gore (JTP10181)
public Gore(origin[3], origin2[3])
{
	new rDistance = get_distance(origin, origin2) ? get_distance(origin, origin2) : 1
	new rX = ((origin[0] - origin2[0]) * 80) / rDistance
	new rY = ((origin[1] - origin2[1]) * 80) / rDistance
	new rZ = ((origin[2] - origin2[2]) * 80) / rDistance
	new rXm = rX >= 0 ? 1 : -1
	new rYm = rY >= 0 ? 1 : -1
	new rZm = rZ >= 0 ? 1 : -1
	
	// Blood
	if (g_BloodNum > 0)
	{
		for (new i = 0; i < 12; i++)
		{
			message_begin(MSG_BROADCAST, SVC_TEMPENTITY)
			write_byte(TE_WORLDDECAL)
			write_coord(origin[0] + random_num(-100, 100))
			write_coord(origin[1] + random_num(-100, 100))
			write_coord(origin[2] - 36)
			write_byte(g_Blood[random_num(0, g_BloodNum - 1)]) // index
			message_end()
		}
	}
	
	// Head
	message_begin(MSG_BROADCAST, SVC_TEMPENTITY)
	write_byte(TE_MODEL)
	write_coord(origin[0])
	write_coord(origin[1])
	write_coord(origin[2]+40)
	write_coord(rX + (rXm * random_num(0, 80)))
	write_coord(rY + (rYm * random_num(0, 80)))
	write_coord(rZ + (rZm * random_num(80, 200)))
	write_angle(random_num(0,360))
	write_short(mdl_gib_Head)
	write_byte(0)
	write_byte(400)
	message_end()
	
	// Parts
	for (new i = 0; i < 4; i++)
	{
		message_begin(MSG_BROADCAST, SVC_TEMPENTITY)
		write_byte(TE_MODEL)
		write_coord(origin[0])
		write_coord(origin[1])
		write_coord(origin[2])
		write_coord(rX + (rXm * random_num(0, 80)))
		write_coord(rY + (rYm * random_num(0, 80)))
		write_coord(rZ + (rZm * random_num(80, 200)))
		write_angle(random_num(0,360))
		write_short(random_num(0, 1) == 0 ? mdl_gib_Flesh : mdl_gib_Meat)
		write_byte(0)
		write_byte(400)
		message_end()
	}
	
	message_begin(MSG_BROADCAST, SVC_TEMPENTITY)
	write_byte(TE_BLOODSPRITE)
	write_coord(origin[0])
	write_coord(origin[1])
	write_coord(origin[2] + 20)
	write_short(mdl_blood_Spray)
	write_short(mdl_blood_Drop)
	write_byte(248)
	write_byte(10)
	message_end()
}

public CreateBeam(origin[3], target[3], color[4], width, life, noise)
{
	message_begin(MSG_BROADCAST, SVC_TEMPENTITY)
	write_byte(0)			// TE_BEAMPOINTS
	write_coord(origin[0])		// start point
	write_coord(origin[1])
	write_coord(origin[2])
	write_coord(target[0])		// end point
	write_coord(target[1])
	write_coord(target[2])
	write_short(mdl_Smoke)		// sprite to draw (precached below)
	write_byte(0)			// starting frame
	write_byte(0)			// frame rate
	write_byte(life)		// life in 0.1s
	write_byte(width)		// line width in 0.1u
	write_byte(noise)		// noise in 0.1u
	write_byte(color[0])		// R
	write_byte(color[1])		// G
	write_byte(color[2])		// B
	write_byte(color[3])		// brightness
	write_byte(1)			// scroll speed
	message_end()
}

public CreateBeamFollow(id, life, width, color[4])
{
	message_begin(MSG_BROADCAST, SVC_TEMPENTITY) 
	write_byte(22)
	write_short(id)
	write_short(mdl_Smoke)
	write_byte(life)
	write_byte(width)
	write_byte(color[0])
	write_byte(color[1])
	write_byte(color[2])
	write_byte(color[3])
	message_end()
}

public KillBeams(id)
{
	message_begin(MSG_BROADCAST, SVC_TEMPENTITY)
	write_byte(99)
	write_short(id)
	message_end()
}

public UpdateMaxSpeed(id) {
	static Float:speed
	
	if (g_InRound) {
		speed = 320.0 * var_Speed
		
		engfunc(EngFunc_SetClientMaxspeed, id, speed)
		set_pev(id, pev_maxspeed, speed)
		
		client_cmd(id, "cl_forwardspeed 9999")
		client_cmd(id, "cl_backspeed 9999")
		client_cmd(id, "cl_sidespeed 9999")
	}
}

public UpdateMaxSpeedA() {
	if (g_InRound) {
		new players[32], pCount
		get_players(players, pCount, "a")
		
		for (new i = 0; i < pCount; i++)
			UpdateMaxSpeed(players[i])
	}
}

public UpdateScores(id)
{
	if (id > 0)
	{
		set_msg_block(msg_ScoreInfo, BLOCK_NOT)
		message_begin(MSG_BROADCAST, msg_ScoreInfo)
		write_byte(id)
		write_short(gp_Score[id][0])
		write_short(gp_Score[id][1])
		write_short(0)
		write_short(get_user_team(id))
		message_end()
		set_msg_block(msg_ScoreInfo, BLOCK_SET)
		
		set_pev(id, pev_frags, float(gp_Score[id][0]))
	}
	else
	{
		set_msg_block(msg_TeamScore, BLOCK_NOT)
		message_begin(MSG_BROADCAST, msg_TeamScore)
		write_string("TERRORIST")
		write_short(g_TeamScore[TEAM_T])
		message_end()
		
		message_begin(MSG_BROADCAST, msg_TeamScore)
		write_string("CT")
		write_short(g_TeamScore[TEAM_CT])
		message_end()
		set_msg_block(msg_TeamScore, BLOCK_SET)
	}
}

// Alles was hier drunter steht:
// DAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAANKE Basic-Master :o
public set_keyvalue(id, key[], value[])
{
	new class[32]
	pev(id, pev_classname, class, 31)
	
	set_kvd(0, KV_ClassName, class)
	set_kvd(0, KV_KeyName, key)
	set_kvd(0, KV_Value, value)
	set_kvd(0, KV_fHandled, 0)
	
	dllfunc(DLLFunc_KeyValue, id, 0)
}

public FakeDamage(id, Float:damage, damagetype)
{
	new tmp[16]
	new ent = engfunc(EngFunc_CreateNamedEntity, engfunc(EngFunc_AllocString, "trigger_hurt"))
	set_keyvalue(ent, "classname", "trigger_hurt")
	
	float_to_str(damage * 2.0, tmp, 15)
	set_keyvalue(ent, "dmg", tmp)
	
	num_to_str(damagetype, tmp, 15)
	set_keyvalue(ent, "damagetype", tmp)
	set_keyvalue(ent, "origin", "8192 8192 8192")
	
	dllfunc(DLLFunc_Spawn, ent)
	dllfunc(DLLFunc_Touch, ent, id)
	engfunc(EngFunc_RemoveEntity, ent)
}

public set_animation(id, anim)
{
	set_pev(id, pev_weaponanim, anim)
	
	message_begin(MSG_ONE_UNRELIABLE, SVC_WEAPONANIM, {0, 0, 0}, id)
	write_byte(anim)
	write_byte(pev(id, pev_body))
	message_end()
}



// Commands
public cmd_Block(id)
{
	return PLUGIN_HANDLED
}

public client_command(id)
{
	static i, arg[12]
	
	if(read_argv(0, arg, 11) > 11)
		return PLUGIN_CONTINUE
	
	for(i = 0; i < 34; i++)
	{
		if(equali(g_Aliases[i], arg) || equali(g_Aliases2[i], arg))
			return PLUGIN_HANDLED
	}
	
	return PLUGIN_CONTINUE 
}

public cmd_SpawnPoint()
{
	
}

// Events
public forward_ResetHUD(id)
{
	gp_Jumps[id] = 0
	gp_InDodge[id] = false
	gp_LastDodge[id] = 0
	gp_LastShot[id] = 0
	
	new Float:origin[3]
	pev(id, pev_origin, origin)
	
	if (var_Effects & EFF_SPAWN)
	{
		message_begin(MSG_BROADCAST, SVC_TEMPENTITY)
		write_byte(11) // quake style spawn sprite
		write_coord(floatround(origin[0]))
		write_coord(floatround(origin[1]))
		write_coord(floatround(origin[2]))
		message_end()
	}
	
	if (var_SpawnProt)
	{
		gp_BlockShoot[id] = true
		set_pev(id, pev_solid, SOLID_NOT)
		
		set_pev(id, pev_renderfx, kRenderFxNone)
		set_pev(id, pev_rendermode, kRenderTransAdd)
		set_pev(id, pev_renderamt, 150.0)
		
		new arr[2]
		arr[0] = id
		set_task(TIME_MAKENORMAL, "task_MakeNormal", _, arr, 1)
	}
	else
	{
		set_pev(id, pev_rendermode, kRenderNormal)
		set_pev(id, pev_renderfx, kRenderFxGlowShell)
		set_pev(id, pev_renderamt, 16.0)
		
		if (get_user_team(id) == TEAM_CT)
			set_pev(id, pev_rendercolor, Float:{0.0, 150.0, 255.0})
		else
			set_pev(id, pev_rendercolor, Float:{255.0, 0.0, 0.0})
	}
}

public task_MakeNormal(params[], task)
{
	new id = params[0]
	
	gp_BlockShoot[id] = false
	set_pev(id, pev_solid, SOLID_BBOX)
	
	set_pev(id, pev_rendermode, kRenderNormal)
	set_pev(id, pev_renderfx, kRenderFxGlowShell)
	set_pev(id, pev_renderamt, 16.0)
	
	if (get_user_team(id) == TEAM_CT)
		set_pev(id, pev_rendercolor, Float:{0.0, 150.0, 255.0})
	else
		set_pev(id, pev_rendercolor, Float:{255.0, 0.0, 0.0})
}

public forward_CurWeapon(id)
{
	UpdateMaxSpeed(id)
	
	if (var_Effects & EFF_CROSSHAIR)
	{
		message_begin(MSG_ONE_UNRELIABLE, get_user_msgid("HideWeapon"), {0, 0, 0}, id)
		write_byte((1<<0) | (1<<5) | (1<<6))
		message_end()
		
		message_begin(MSG_ONE_UNRELIABLE, get_user_msgid("Crosshair"), {0, 0, 0}, id)
		write_byte(2)
		message_end()
	}
	
	new arr[2]
	arr[0] = id
	set_task(0.2, "forward_CurWeapon2", _, arr, 1)
}

public forward_CurWeapon2(params[], task)
{
	if (is_user_alive(params[0]))
	{
		// Mache das Crosshair schoen klein :o
		new clip, ammo
		if (get_user_weapon(params[0], clip, ammo) == CSW_M4A1)
			StripWeapons(params[0])
		else
		{
			new item = engfunc(EngFunc_CreateNamedEntity, engfunc(EngFunc_AllocString, "weapon_m4a1"))
			if (item)
			{
				new Float:origin[3]
				pev(params[0], pev_origin, origin)
				
				set_pev(item, pev_origin, origin)
				set_pev(item, pev_spawnflags, pev(item, pev_spawnflags) | SF_NORESPAWN) 
				
				dllfunc(DLLFunc_Spawn, item)
				
				new save = pev(item, pev_solid)
				dllfunc(DLLFunc_Touch, item, params[0])
				
				if(pev(item, pev_solid) == save)
					engfunc(EngFunc_RemoveEntity, item)
				
				client_cmd(params[0], "use weapon_m4a1")
			}
		}
		
		set_pev(params[0], pev_weaponmodel, mdl_pWeapon)
		set_pev(params[0], pev_viewmodel, mdl_vWeapon)
	}
}

public forward_RoundStart()
{
	g_InRound = true
	set_task(0.2, "UpdateMaxSpeedA")
}

public forward_RoundEnd()
{
	if (g_InRound)
		g_InRound = false
}

public forward_RoundDraw()
{
	g_InRound = false
}

public forward_ResetGame()
{
	g_InRound = false
	
	ResetVars(0)
	UpdateScores(0)
	
	for (new i = 0; i < 33; i++)
	{
		gp_Score[i] = {0, 0}
		UpdateScores(i)
	}
}

// Forwards
public client_disconnect(id)
{
	ResetVars(id)
}

public client_putinserver(id)
{
	ResetVars(id)
	UpdateScores(0)
	
	new players[32], pCount
	get_players(players, pCount)
	for (new i = 0; i < pCount; i++)
		UpdateScores(players[i])
}

public forward_PlayerPreThink(id)
{
	static buttons, oldbuttons, key, i
	static flags, oldflags_array[33], oldflags
	
	buttons = pev(id, pev_button)
	oldbuttons = pev(id, pev_oldbuttons)
	
	flags = pev(id, pev_flags)
	oldflags = oldflags_array[id]
	
	for (i = 0; i < 16; i++)
	{
		key = 1 << i
		if (buttons & key)
		{
			if (!(oldbuttons & key))
			{
				fwd_Button(id, key, true, gp_ButtonTime[id][i] == 0 ? -1 : tickcount() - gp_ButtonTime[id][i])
				gp_ButtonTime[id][i] = tickcount()
			}
		}
		else if (oldbuttons & key)
		{
			if (!(buttons & key))
				fwd_Button(id, key, false, -1)
		}
	}
	
	if (is_user_alive(id))
	{
		if (flags & FL_ONGROUND && !(oldflags & FL_ONGROUND))
		{
			gp_Jumps[id] = 0
			
			if (gp_InDodge[id])
			{
				gp_InDodge[id] = false
				gp_LastDodge[id] = tickcount()
				KillBeams(id)
			}
		}
		else if (oldflags & FL_ONGROUND && !(flags & FL_ONGROUND))
		{
			if (gp_InDodge[id])
			{
				// Feuer :o
				// CreateBeamFollow(id, 4, 4, {255, 0, 0, 196})
				// CreateBeamFollow(id, 3, 3, {255, 200, 0, 196})
				// CreateBeamFollow(id, 2, 2, {50, 50, 255, 196})
				
				if (var_Effects & EFF_DODGE)
				{
					if (get_user_team(id) == TEAM_CT)
					{
						CreateBeamFollow(id, 10, 4, {0, 0, 255, 196})
						CreateBeamFollow(id, 8, 3, {0, 150, 255, 196})
						CreateBeamFollow(id, 6, 2, {255, 255, 255, 196})
					}
					else
					{
						CreateBeamFollow(id, 10, 4, {255, 0, 0, 196})
						CreateBeamFollow(id, 8, 3, {255, 50, 0, 196})
						CreateBeamFollow(id, 6, 2, {255, 255, 255, 196})
					}
					
					client_cmd(id, "play instagibx/jump.wav")
				}
			}
		}
		
		// Kein Langsamwerden nach einem Sprung
		set_pev(id, pev_fuser2, 0.0)
	}
	
	oldflags_array[id] = flags
	return FMRES_IGNORED
}

public fwd_Button(id, key, bool:pressed, btime)
{
	if (pressed && is_user_alive(id))
	{
		switch (key)
		{
			case IN_ATTACK2:
			{
				switch (var_Zoom)
				{
					case 0: cs_set_user_zoom(id, CS_SET_NO_ZOOM, 1)
					case 1:
					{
						if (cs_get_user_zoom(id) == CS_SET_AUGSG552_ZOOM)
							cs_set_user_zoom(id, CS_SET_NO_ZOOM, 1)
						else
							cs_set_user_zoom(id, CS_SET_AUGSG552_ZOOM, 1)
					}
					case 2:
					{
						switch (cs_get_user_zoom(id))
						{
							case CS_SET_NO_ZOOM: cs_set_user_zoom(id, CS_SET_FIRST_ZOOM, 1)
							case CS_SET_FIRST_ZOOM: cs_set_user_zoom(id, CS_SET_SECOND_ZOOM, 1)
							default: cs_set_user_zoom(id, CS_SET_NO_ZOOM, 1)
						}
					}
				}
			}
			case IN_ATTACK:
			{
				if (g_InRound && !gp_BlockShoot[id] && abs(tickcount() - gp_LastShot[id]) >= TIME_DELTA_SHOOT)
				{
					new team = get_user_team(id), vieworigin[3], aimorigin[3]
					get_user_origin(id, vieworigin, 1)
					get_user_origin(id, aimorigin, 3)
					
					if (var_Effects & EFF_BAR)
					{
						message_begin(MSG_ONE_UNRELIABLE, get_user_msgid("BarTime"), {0, 0, 0}, id)
						write_short(TIME_DELTA_SHOOT / 1000)
						message_end()
					}
					
					if (var_Effects & EFF_SHOOT)
					{
						// Mache 'nen netten Screenfade :>
						message_begin(MSG_ONE_UNRELIABLE, msg_ScreenFade, {0, 0, 0}, id)
						write_short(TIME_DELTA_SHOOT * 5)
						write_short(100)
						write_short(FFADE_OUT)
												
						if (team == TEAM_CT)
						{
							write_byte(0)
							write_byte(150)
							write_byte(255)
						}
						else
						{
							write_byte(255)
							write_byte(50)
							write_byte(0)
						}
						
						write_byte(100)
						message_end()
					
						// Erstelle den Beam
						if (team == TEAM_CT)
						{
							CreateBeam(vieworigin, aimorigin, {0, 0, 255, 196}, 20, 5, 1)
							CreateBeam(vieworigin, aimorigin, {0, 150, 255, 196}, 15, 5, 1)
							CreateBeam(vieworigin, aimorigin, {255, 255, 255, 196}, 5, 5, 3)
						}
						else
						{
							CreateBeam(vieworigin, aimorigin, {255, 0, 0, 196}, 20, 5, 1)
							CreateBeam(vieworigin, aimorigin, {255, 50, 0, 196}, 15, 5, 1)
							CreateBeam(vieworigin, aimorigin, {255, 255, 255, 196}, 5, 5, 3)
						}
					}
					
					if (var_Effects & EFF_STEAM)
					{
						message_begin(MSG_BROADCAST, SVC_TEMPENTITY)
						write_byte(5)
						write_coord(aimorigin[0])
						write_coord(aimorigin[1])
						write_coord(aimorigin[2])
						write_short(mdl_Steam)
						write_byte(20)
						write_byte(25)
						message_end()
					}
					
					// Erstelle den Sound
					emit_sound(id, CHAN_AUTO, "instagibx/fire.wav", VOL_NORM, ATTN_NONE, 0, PITCH_NORM)
					
					// Setze Waffenanimation
					set_pev(id, pev_animtime, 1.0)
					set_animation(id, 3)
					
					// Mache Spieler tot unso
					new aim, body
					get_user_aiming(id, aim, body)
					if (aim)
					{
						new class[32]
						pev(aim, pev_classname, class, 31)
						
						if (equal(class, "player"))
						{
							new aimteam = get_user_team(aim)
							if (var_Gamemode == GAME_DM || aimteam != team)
							{
								set_msg_block(msg_DeathMsg, BLOCK_ONCE)
								dllfunc(DLLFunc_ClientKill, aim)
								
								message_begin(MSG_BROADCAST, msg_DeathMsg)
								write_byte(id)
								write_byte(aim)
								write_byte(body == 1 ? 1 : 0)
								write_string("a lightning gun")
								message_end()
								
								if (body == 1)
								{
									gp_Score[id][0] += POINTS_HEADSHOT
									g_TeamScore[team] += POINTS_HEADSHOT
									
									if (var_Comments)
									{
										new name[32]
										get_user_name(id, name, 31)
										set_hudmessage(0, 0, 255, _, _, 1, 0.1, 3.0, 0.5, 0.5, -1)
										ShowSyncHudMsg(0, sync_Comment, TXT_HEADSHOT, name)
										
										client_cmd(0, "play instagibx/headshot")
									}
								}
								else
								{
									gp_Score[id][0] += POINTS_DEFAULT
									
									if (var_Gamemode == GAME_TDM)
										g_TeamScore[team] += POINTS_DEFAULT
								}
								
								if (var_Effects & (EFF_GORE | EFF_GORE_SMOKE))
								{
									new hitorigin[3]
									get_user_origin(aim, hitorigin)
									
									if (var_Effects & EFF_GORE_SMOKE)
									{
										message_begin(MSG_BROADCAST, SVC_TEMPENTITY)
										write_byte(5)
										write_coord(hitorigin[0])
										write_coord(hitorigin[1])
										write_coord(hitorigin[2])
										write_short(mdl_Steam)
										write_byte(30)
										write_byte(25)
										message_end()
									}
									
									if (var_Effects & EFF_GORE)
									{
	
										new origin[3]
										get_user_origin(id, origin)
										
										// Verstecke den Körper
										set_pev(aim, pev_origin, {8092.0, 8092.0, 8092.0})
										
										// Bluuuuuutt!!11
										Gore(hitorigin, origin)
									}
								}
								
								gp_Score[aim][1]++
								
								UpdateScores(id)
								UpdateScores(aim)
								UpdateScores(aimteam)
								UpdateScores(0)
							}
						}
						else if (equal(class, "func_breakable"))
							FakeDamage(aim, 100.0, DMG_BULLET)
					}
					
					gp_LastShot[id] = tickcount()
				}
			}
			case IN_JUMP:
			{
				if (!gp_InDodge[id] && !(pev(id, pev_flags) & FL_ONGROUND) && gp_Jumps[id] < var_MaxJumps)
				{
					new Float:velocity[3]
					pev(id, pev_velocity, velocity)
					
					if (velocity[2] >= 0.0)
					{
						velocity[2] = 250.0
						set_pev(id, pev_velocity, velocity)
						
						gp_Jumps[id]++
					}
				}
			}
			default:
			{
				if (g_InRound && key & (IN_FORWARD | IN_BACK | IN_MOVELEFT | IN_MOVERIGHT))
				{
					new Float:dodge = var_Dodge
					
					if (dodge > 0.0
					    && btime <= TIME_DODGE
					    && !gp_InDodge[id]
					    && abs(tickcount() - gp_LastDodge[id]) >= TIME_DELTA_DODGE
					    && pev(id, pev_flags) & FL_ONGROUND)
					{
						// Prüfe, ob keine andere Bewegungstaste gedrückt ist
						new buttons = pev(id, pev_button)
						if (((buttons & IN_FORWARD ? IN_FORWARD : 0) | (buttons & IN_BACK ? IN_BACK : 0) | (buttons & IN_MOVELEFT ? IN_MOVELEFT : 0) | (buttons & IN_MOVERIGHT ? IN_MOVERIGHT : 0)) - key == 0)
						{
							new Float:vector[3]
							
							pev(id, pev_v_angle, vector)
							engfunc(EngFunc_MakeVectors, vector)
							
							switch (key)
							{
								case IN_FORWARD: global_get(glb_v_forward, vector)
								case IN_MOVERIGHT: global_get(glb_v_right, vector)
								case IN_BACK:
								{
									global_get(glb_v_forward, vector)
									vector[0] = -vector[0]
									vector[1] = -vector[1]
								}
								case IN_MOVELEFT:
								{
									global_get(glb_v_right, vector)
									vector[0] = -vector[0]
									vector[1] = -vector[1]
								}
							}
							
							vector[0] *= dodge
							vector[1] *= dodge
							vector[2] = 250.0
							set_pev(id, pev_velocity, vector)
							
							gp_InDodge[id] = true
						}
					}
				}
			}
		}
	}
}
