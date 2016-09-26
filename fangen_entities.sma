// i prefer a rather strict and clean coding style.. ;)
#pragma semicolon 1

#include <amxmodx>
#include <fakemeta>
#include <xs>

public plugin_init() {
	register_plugin("Fangen Entities", "0.1", "p4ddY");
	
	register_clcmd("origin", "bla");
	
	//CreateJumpPad(Float:{-176.131423, 299.819854, 36.031250}, Float:{0.936704, 0.350120, 5.0}, 200.0);
	CreateTeleporter(Float:{-176.131423, 299.819854, 50.031250}, Float:{803.636169, 431.992614, 837.530395}, Float:{0.0, 1.0, 0.01});
	
	register_forward(FM_Touch, "FwdTouch");
	register_forward(FM_Think, "FwdThink");
	register_forward(FM_PlayerPostThink, "FwdPlayerPostThink");
}

public bla(id) {
	new Float:origin[3], Float:velocity[3];
	
	pev(id, pev_origin, origin);
	pev(id, pev_velocity, velocity);
	
	xs_vec_normalize(velocity, velocity);
	
	client_print(id, print_chat, "jeah %f %f %f and %f %f %f", origin[0], origin[1], origin[2], velocity[0], velocity[1], velocity[2]);
}

public plugin_precache() {
	precache_model("models/pallet.mdl");
	precache_model("sprites/e-tele1.spr");
}

CreateJumpPad(const Float:origin[3], const Float:direction[3], Float:speed) {
	static Float:mins[3] = {-27.260000, -22.280001, -22.290001};
	static Float:maxs[3] = {27.340000, 26.629999, -12.290001};

	new ent = engfunc(EngFunc_CreateNamedEntity, engfunc(EngFunc_AllocString, "info_target"));
	if (!ent)
		return 0;
	
	set_pev(ent, pev_classname, "fangen_jumppad");
	engfunc(EngFunc_SetModel, ent, "models/pallet.mdl");
	
	dllfunc(DLLFunc_Spawn, ent);
	
	engfunc(EngFunc_SetSize, ent, mins, maxs);
	set_pev(ent, pev_mins, mins);
	set_pev(ent, pev_maxs, maxs);
	set_pev(ent, pev_absmin, mins);
	set_pev(ent, pev_absmax, maxs);
	
	set_pev(ent, pev_movetype, MOVETYPE_TOSS);
	set_pev(ent, pev_solid, SOLID_BBOX);
	
	engfunc(EngFunc_SetOrigin, ent, origin);
	
	set_pev(ent, pev_vuser1, direction);
	set_pev(ent, pev_fuser1, speed);
	
	return ent;
}

public FwdThink(id) {
	static classname[32];
	
	pev(id, pev_classname, classname, charsmax(classname));
	if (equal(classname, "fangen_teleport")) {
		static Float:origin[3];
		pev(id, pev_origin, origin);
		
		static ent;
		while ((ent = engfunc(EngFunc_FindEntityInSphere, ent, origin, 32.0))) {
			if (id != ent) {
				static class[32];
				pev(ent, pev_classname, class, charsmax(class));
				
				if (equal(class, "player") && is_user_alive(ent)) {
					new Float:direction[3], destiny[3];
					pev(id, pev_vuser1, direction);
					pev(id, pev_vuser2, destiny);
					
					new Float:velocity[3], Float:speed;
					pev(ent, pev_velocity, velocity);
					speed = floatsqroot(velocity[0] * velocity[0] + velocity[1] * velocity[1] + velocity[2] * velocity[2]);
					
					velocity[0] = direction[0] * speed;
					velocity[1] = direction[1] * speed;
					velocity[2] = direction[2] * speed;
					
					set_pev(ent, pev_origin, destiny);
					set_pev(ent, pev_velocity, velocity);
					
					new Float:angles[3];
					vector_to_angle(direction, angles);
					set_pev(ent, pev_fixangle, 1.0);
					set_pev(ent, pev_angles, angles);
					
					message_begin(MSG_BROADCAST, SVC_TEMPENTITY);
					write_byte(TE_IMPLOSION);
					write_coord(floatround(origin[0]));
					write_coord(floatround(origin[1]));
					write_coord(floatround(origin[2]));
					write_byte(100);
					write_byte(20);
					write_byte(5);
					message_end();
					
					message_begin(MSG_ONE_UNRELIABLE, get_user_msgid("ScreenFade"), _, ent);
					write_short(floatround((1<<12) * 0.5));
					write_short(floatround((1<<12) * 0.0));
					write_short((1<<1));
					write_byte(255);
					write_byte(0);
					write_byte(255);
					write_byte(150);
					message_end();
				}
			}
		}
		
		new Float:curframe;
		pev(id, pev_frame, curframe);
		curframe = curframe >= 25.0 ? 1.0 : curframe + 1.0;
		set_pev(id, pev_frame, curframe);
		
		set_pev(id, pev_nextthink, get_gametime() + 0.05);
	}
}

public CreateTeleporter(const Float:origin[3], const Float:destiny[3], const Float:direction[3]) {
	new ent = engfunc(EngFunc_CreateNamedEntity, engfunc(EngFunc_AllocString, "info_target"));
	if (!ent)
		return 0;
	
	set_pev(ent, pev_classname, "fangen_teleport");
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

public FwdTouch(toucher, touched) {
	static classToucher[32], classTouched[32];
	
	pev(toucher, pev_classname, classToucher, charsmax(classToucher));
	pev(touched, pev_classname, classTouched, charsmax(classTouched));
	
	if (equal(classToucher, "player") && equal(classTouched, "fangen_teleport")) {
		client_print(0, print_chat, "teleport");
	}
}
