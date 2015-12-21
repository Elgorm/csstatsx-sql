/*
*	CSStatsX MySQL			     	  v. 0.3
*	by serfreeman1337	     	 http://1337.uz/
*/

#include <amxmodx>
#include <sqlx>

#include <fakemeta>
#include <hamsandwich>

#define PLUGIN "CSStatsX MySQL"
#define VERSION "0.3"
#define AUTHOR "serfreeman1337"	// AKA SerSQL1337

#define LASTUPDATE "19, December (12), 2015"

#define MYSQL_HOST	"localhost"
#define MYSQL_USER	"root"
#define MYSQL_PASS	""
#define MYSQL_DB	"amxx"

#if AMXX_VERSION_NUM < 183
	#define MAX_PLAYERS 32
	new MaxClients
#endif

/* - SQL - */

new Handle:sql
new Handle:sql_con

/* -  ��������� - */

enum _:sql_que_type	// ��� sql �������
{
	SQL_DUMMY,
	SQL_LOAD,	// �������� ����������
	SQL_UPDATE,	// ����������
	SQL_INSERT,	// �������� ����� ������
	SQL_UPDATERANK	// ��������� ������ �������
}

enum _:load_state_type	// ��������� ��������� ����������
{
	LOAD_NO,	// ������ ���
	LOAD_WAIT,	// �������� ������
	LOAD_OK,	// ���� ������
	LOAD_NEW,	// ����� ������
	LOAD_UPDATE	// ������������� ����� ����������
}

enum _:row_ids		// ������� �������
{
	ROW_ID,
	ROW_IP,
	ROW_STEAMID,
	ROW_NAME,
	ROW_KILLS,
	ROW_DEATHS,
	ROW_HS,
	ROW_TKS,
	ROW_SHOTS,
	ROW_HITS,
	ROW_DMG,
	ROW_BOMBDEF,
	ROW_BOMBDEFUSED,
	ROW_BOMBPLANTS,
	ROW_BOMBEXPLOSIONS,
	ROW_HITSARRAY,
	ROW_FIRSTJOIN,
	ROW_LASTJOIN
}

new const row_names[row_ids][] = // ����� ��������
{
	"id",
	"ip",
	"steamid",
	"name",
	"kills",
	"deaths",
	"hs",
	"tks",
	"shots",
	"hits",
	"dmg",
	"bombdef",
	"bombdefused",
	"bombplants",
	"bombexplosions",
	"hits_xml",
	"first_join",
	"last_join"
}

enum _:STATS
{
	STATS_KILLS,
	STATS_DEATHS,
	STATS_HS,
	STATS_TK,
	STATS_SHOTS,
	STATS_HITS,
	STATS_DMG,
	
	STATS_END
}

enum _:KILL_EVENT
{
	NORMAL,
	SUICIDE,
	WORLD,
	WORLDSPAWN
}

const QUERY_LENGTH =	1216	// ������ ���������� sql �������

#define STATS2_DEFAT	0
#define STATS2_DEFOK	1
#define STATS2_PLAAT	2
#define STATS2_PLAOK	3

new const task_rankupdate	=	31337
new const task_confin		=	21337

new const m_LastHitGroup 		=	75

#define MAX_WEAPONS		CSW_P90 + 1
#define HIT_END			HIT_RIGHTLEG + 1	

/* - ��������� ������ - */

enum _:player_data_struct
{
	PLAYER_ID,		// �� ������ � ���� ������
	PLAYER_LOADSTATE,	// ��������� �������� ���������� ������
	PLAYER_RANK,		// ���� ������
	PLAYER_STATS[8],	// ���������� ������
	PLAYER_STATSLAST[8],	// ������� � ����������
	PLAYER_HITS[8],		// ���������� ���������
	PLAYER_HITSLAST[8],	// ������� � ���������� ���������
	PLAYER_STATS2[4],	// ���������� cstrike
	PLAYER_STATS2LAST[4]	// �������
}

enum _:stats_cache_struct	// ����������� ��� get_stats
{
	CACHE_NAME[32],
	CACHE_STEAMID[30],
	CACHE_STATS[8],
	CACHE_HITS[8],
	bool:CACHE_LAST
}

enum _:cvar_set
{
	CVAR_UPDATESTYLE
}

/* - ���������� - */

new player_data[MAX_PLAYERS + 1][player_data_struct]
new statsnum
new track_set

new cnt_fail,cnt_thd,cnt_nthd,cnt_int

new cvar[cvar_set]

new Trie:stats_cache_trie	// ������ ���� ��� get_stats // ���� - ����

/* - CSSTATS CORE - */

// wstats
new player_wstats[MAX_PLAYERS + 1][MAX_WEAPONS][STATS_END]
new player_whits[MAX_PLAYERS + 1][MAX_WEAPONS][HIT_END]

// wrstats rstats
new player_wrstats[MAX_PLAYERS + 1][MAX_WEAPONS][STATS_END]
new player_wrhits[MAX_PLAYERS + 1][MAX_WEAPONS][HIT_END]

// vstats
new player_vstats[MAX_PLAYERS + 1][MAX_PLAYERS + 1][STATS_END]
new player_vhits[MAX_PLAYERS + 1][MAX_PLAYERS + 1][HIT_END]
new player_vwname[MAX_PLAYERS + 1][MAX_PLAYERS + 1][32]

// astats
new player_astats[MAX_PLAYERS + 1][MAX_PLAYERS + 1][STATS_END]
new player_ahits[MAX_PLAYERS + 1][MAX_PLAYERS + 1][HIT_END]
new player_awname[MAX_PLAYERS + 1][MAX_PLAYERS + 1][32]

new guns_sc_fwd

new const guns_sc[][] = {
	"events/awp.sc",
	"events/g3sg1.sc",
	"events/ak47.sc",
	"events/scout.sc",
	"events/m249.sc",
	"events/m4a1.sc",
	"events/sg552.sc",
	"events/aug.sc",
	"events/sg550.sc",
	"events/m3.sc",
	"events/xm1014.sc",
	"events/usp.sc",
	"events/mac10.sc",
	"events/ump45.sc",
	"events/fiveseven.sc",
	"events/p90.sc",
	"events/deagle.sc",
	"events/p228.sc",
	"events/glock18.sc",
	"events/mp5n.sc",
	"events/tmp.sc",
	"events/elite_left.sc",
	"events/elite_right.sc",
	"events/galil.sc",
	"events/famas.sc"
}

new guns_sc_bitsum

new FW_Death
new FW_Damage

new dummy_ret

// �������� ������� ����������

public plugin_precache()
{
	guns_sc_fwd = register_forward(FM_PrecacheEvent, "FMHook_PrecacheEvent",true)
}

public FMHook_PrecacheEvent(type, name[])
{
	for (new i; i < sizeof guns_sc; i++)
	{
		if(strcmp(guns_sc[i],name) == 0)
		{
			guns_sc_bitsum |= (1 << get_orig_retval())
			
			return FMRES_HANDLED
		}
	}
		
	return FMRES_IGNORED
}

public plugin_init()
{
	register_plugin(PLUGIN,VERSION,AUTHOR)
	register_cvar("csstats_mysql", VERSION, FCVAR_SERVER | FCVAR_SPONLY | FCVAR_UNLOGGED)
	
	track_set = get_cvar_pointer("csstats_rank")
	
	if(!track_set)
		track_set = register_cvar("csstats_rank","0")
	
	/*
	* ��� ��������� ���������� ������ � ��
	*	-2 			- ��� ������ � �����������
	*	-1			- � ����� ������ � �����������
	*	0 			- ��� �����������
	*	�������� ������ 0 	- ����� ��������� ���-�� ������ � �����������
	*/
	cvar[CVAR_UPDATESTYLE] = register_cvar("csstats_mysql_update","-2")
	
	register_logevent("logevent_round_end", 2, "1=Round_End") 
	
	#if AMXX_VERSION_NUM < 183
	MaxClients = get_maxplayers()
	#endif
	
	unregister_forward(FM_PrecacheEvent,guns_sc_fwd,true)
	
	RegisterHam(Ham_Killed,"player","HamHook_PlayerKilled",true)
	RegisterHam(Ham_TakeDamage,"player","HamHook_PlayerDamage",true)
	register_forward(FM_PlaybackEvent, "FMHook_PlaybackEvent")
	
	FW_Death = CreateMultiForward("client_death",ET_IGNORE,FP_CELL,FP_CELL,FP_CELL,FP_CELL,FP_CELL)
	FW_Damage = CreateMultiForward("client_damage",ET_IGNORE,FP_CELL,FP_CELL,FP_CELL,FP_CELL,FP_CELL,FP_CELL)
}

is_tk(killer,victim)
{
	if(killer == victim)
		return true
		
	return false
}

/*
* ������� ��������, ������, ������� � ��������
*/
public HamHook_PlayerKilled(victim,killer)
{
	if(victim <= 0 || victim > MaxClients)
	{
		return HAM_IGNORED
	}
	
	new wpn_id = 0
	new hit_place = 0
	
	if(0 < killer <= MaxClients)
	{
		new inflictor = pev(victim, pev_dmg_inflictor)
		
		if(killer == inflictor) // ��������� ID ������
		{
			wpn_id = get_user_weapon(killer)
		}
		else
		{
			if(inflictor < MaxClients)
				return HAM_IGNORED
			
			// TODO: ��������� �����������
		}
		
		// ������ ����� ���������
		hit_place = get_pdata_int(victim, m_LastHitGroup)
		
		if(!is_tk(killer,victim))
		{
			player_wstats[killer][0][STATS_KILLS] ++
			player_wstats[killer][wpn_id][STATS_KILLS] ++
			
			player_wrstats[killer][0][STATS_KILLS] ++
			player_wrstats[killer][wpn_id][STATS_KILLS] ++
			
			player_vstats[killer][victim][STATS_KILLS] ++
			
			if(hit_place == HIT_HEAD)
			{
				player_wstats[killer][0][STATS_HS] ++
				player_wstats[killer][wpn_id][STATS_HS] ++
				
				player_wrstats[killer][0][STATS_HS] ++
				player_wrstats[killer][wpn_id][STATS_HS] ++
				
				player_vstats[killer][victim][STATS_HS] ++
			}
		}
		else
		{
			player_wstats[killer][0][STATS_TK] ++
			player_wstats[killer][wpn_id][STATS_TK] ++
			
			player_wrstats[killer][0][STATS_TK] ++
			player_wrstats[killer][wpn_id][STATS_TK] ++
			
			player_vstats[killer][victim][STATS_TK] ++
		}
	}
	
	player_wstats[victim][0][STATS_DEATHS] ++
	player_wrstats[victim][0][STATS_DEATHS] ++
	
	if(wpn_id)
	{
		player_wstats[victim][wpn_id][STATS_DEATHS] ++
		player_wrstats[victim][wpn_id][STATS_DEATHS] ++
		
		player_astats[victim][killer][STATS_DEATHS] ++
	}
	
	ExecuteForward(FW_Death,dummy_ret,killer,victim,wpn_id,hit_place,is_tk(killer,victim))
	client_death(killer,victim)
	
	return HAM_IGNORED
}

/*
* ������� ��������� � ����
*/
public HamHook_PlayerDamage(victim, inflictor, attacker, Float:damage, damagebits)
{
	if(victim <= 0 || victim > MaxClients)
	{
		return HAM_IGNORED
	}
	
	if(!(0 < attacker <= MaxClients))
	{
		return HAM_IGNORED
	}
	
	new wpn_id, hit_place = get_pdata_int(victim, m_LastHitGroup)
	
	if(inflictor == attacker)
	{
		wpn_id = get_user_weapon(attacker)
	}
	else
	{
		// TODO: ��������� �����������
	}
	
	//
	// https://pp.vk.me/c630529/v630529638/72ec/1plPtx18WMo.jpg
	//
	
	player_wstats[attacker][0][STATS_HITS] ++
	player_wstats[attacker][0][STATS_DMG] += floatround(damage)
	player_whits[attacker][0][hit_place] ++
	
	player_wrstats[attacker][0][STATS_HITS] ++
	player_wrstats[attacker][0][STATS_DMG] += floatround(damage)
	player_wrhits[attacker][0][hit_place] ++
	
	player_vstats[attacker][victim][STATS_HITS] ++
	player_vstats[attacker][victim][STATS_DMG] += floatround(damage)
	player_vhits[attacker][victim][hit_place] ++
	
	player_astats[victim][attacker][STATS_HITS] ++
	player_astats[victim][attacker][STATS_DMG] += floatround(damage)
	player_ahits[victim][attacker][hit_place] ++
	
	if(wpn_id)
	{
		player_wstats[attacker][wpn_id][STATS_DMG] += floatround(damage)
		player_wrstats[attacker][wpn_id][STATS_DMG] += floatround(damage)
		player_whits[attacker][wpn_id][hit_place] ++
		player_wrhits[attacker][wpn_id][hit_place] ++
	}
	
	ExecuteForward(FW_Damage,dummy_ret,attacker,victim,floatround(damage),wpn_id,hit_place,is_tk(attacker,victim))
	
	return HAM_IGNORED
}

get_user_wstats(index, wpnindex, stats[8], bh[8])
{
	for(new i ; i < STATS_END ; i++)
	{
		stats[i] = player_wstats[index][wpnindex][i]
	}
	
	#define krisa[%1] player_whits[index][wpnindex][%1]
	
	for(new i ; i < HIT_END ; i++)
	{
		bh[i] = krisa[i]
	}
}

get_user_wrstats(index, wpnindex, stats[8], bh[8])
{
	for(new i ; i < STATS_END ; i++)
	{
		stats[i] = player_wrstats[index][wpnindex][i]
	}
	
	for(new i ; i < HIT_END ; i++)
	{
		bh[i] = player_wrhits[index][wpnindex][i]
	}
}

get_user_rstats(index, stats[8], bh[8])
{
	for(new i ; i < STATS_END ; i++)
	{
		stats[i] = player_wrstats[index][0][i]
	}
	
	for(new i ; i < HIT_END ; i++)
	{
		bh[i] = player_wrhits[index][0][i]
	}
}

get_user_stats2(index, stats[4])
{
	// warning fix serf style 8)
	if(index && stats[0])
	{
	}
	
	return 0
}

reset_user_wstats(index)
{
	for(new i ; i < MAX_WEAPONS ; i++)
	{
		arrayset(player_wrstats[index][i],0,STATS_END)
		arrayset(player_wrhits[index][i],0,HIT_END)
	}
	
	for(new i ; i < MAX_PLAYERS + 1 ;i++)
	{
		arrayset(player_vstats[index][i],0,MAX_PLAYERS + 1)
		arrayset(player_vhits[index][i],0,MAX_PLAYERS + 1)
		
		arrayset(player_astats[index][i],0,MAX_PLAYERS + 1)
		arrayset(player_ahits[index][i],0,MAX_PLAYERS + 1)
	}
	
	return true
}

reset_user_allstats(index)
{
	for(new i ; i < MAX_WEAPONS ; i++)
	{
		arrayset(player_wstats[index][i],0,STATS_END)
		arrayset(player_whits[index][i],0,HIT_END)
	}
	
	return true
}

/*
* 
*/
public FMHook_PlaybackEvent(flags, invoker, eventid) {
	if (!(guns_sc_bitsum & (1 << eventid)) || !(1 <= invoker <= MaxClients))
		return FMRES_IGNORED

	#define get_meteor_sunstrike(%1) get_user_weapon(%1)
		
	new wpn_id = get_meteor_sunstrike(invoker)
	
	server_print("--> %d shooting from %d pizdec",invoker,wpn_id)
	
	player_wstats[invoker][0][STATS_SHOTS] ++
	player_wstats[invoker][wpn_id][STATS_SHOTS] ++
	
	player_wrstats[invoker][0][STATS_SHOTS] ++
	player_wrstats[invoker][wpn_id][STATS_SHOTS] ++

	return FMRES_HANDLED
}

public plugin_cfg()
{
	sql = SQL_MakeDbTuple(MYSQL_HOST,MYSQL_USER,MYSQL_PASS,MYSQL_DB)
	
	// ���������� ���������� � �� ������ n ���
	if(get_pcvar_num(cvar[CVAR_UPDATESTYLE]) > 0)
	{
		set_task(
			float(get_pcvar_num(cvar[CVAR_UPDATESTYLE])),
			"DB_SaveAll",
			.flags = "b"
		)
	}
}

/*
* ��������� ���������� ��� �����������
*/
public client_putinserver(id)
{
	arrayset(player_data[id],0,player_data_struct)
	reset_user_allstats(id)
	reset_user_wstats(id)
	
	DB_LoadPlayerData(id)
}

/*
* ��������� ���������� ��� �����������
*/
public client_disconnect(id)
{
	DB_SavePlayerData(id)
}

/*
* ��������� ���������� ����� ������
*/
public client_death(killer,victim)
{
	server_print("--> DEATH %d %d",killer,victim)
	
	// ��������� ���������� � �� ��� ������
	if(get_pcvar_num(cvar[CVAR_UPDATESTYLE]) == -2)
	{
		DB_SavePlayerData(victim)
	}
}

/*
* ��������� ���� ������
*/
public client_infochanged(id)
{
	new cur_name[32],new_name[32]
	get_user_name(id,cur_name,charsmax(cur_name))
	get_user_info(id,"name",new_name,charsmax(new_name))
	
	if(strcmp(cur_name,new_name) != 0)
	{
		DB_SavePlayerData(id,true)
	}
}

/*
* ��������� ���������� � ����� ������
*/
public logevent_round_end()
{
	if(get_pcvar_num(cvar[CVAR_UPDATESTYLE]) == -1)
	{
		DB_SaveAll()
	}
}

public save_test(id)
{
	DB_SavePlayerData(id)
}

public plugin_natives()
{
	register_library("xstats")
	
	register_native("get_user_wstats","native_get_user_wstats")
	register_native("get_user_wrstats","native_get_user_wrstats")
	register_native("get_user_stats","native_get_user_stats")
	register_native("get_user_rstats","native_get_user_rstats")
	register_native("get_user_vstats","native_get_user_vstats")
	register_native("get_user_astats","native_get_user_astats")
	register_native("reset_user_wstats","native_reset_user_wstats")
	register_native("get_stats","native_get_stats")
	register_native("get_statsnum","native_get_statsnum")
	register_native("get_user_stats2","native_get_user_stats2")
	register_native("get_stats2","native_get_stats2")
	
	register_native("xmod_get_wpnname","native_xmod_get_wpnname")
	register_native("xmod_get_maxweapons","native_xmod_get_maxweapons")
}


public native_xmod_get_wpnname(plugin_id,params)
{
	new wpn_id = get_param(1)
	new weapon_name[32]
	
	get_weaponname(wpn_id,weapon_name,charsmax(weapon_name))
	set_string(2,weapon_name,get_param(3))
	
	return strlen(weapon_name)
}

public native_xmod_get_maxweapons(plugin_id,params)
{
	return MAX_WEAPONS
}

/*
* ���������� �� ������� ������
*
* native get_user_wstats(index, wpnindex, stats[8], bodyhits[8])
*/
public native_get_user_wstats(plugin_id,params)
{
	new id = get_param(1)
	
	if(!(0 < id <= MaxClients))	// ������� ����� ���� ������
	{
		log_error(AMX_ERR_NATIVE,"Player index out of bounds (%d)",id)
		
		return false
	}
	
	new wpn_id = get_param(2)
	
	if(wpn_id != 0 && !(0 < wpn_id < MAX_WEAPONS))
	{
		log_error(AMX_ERR_NATIVE,"Weapon index out of bounds (%d)",id)
		
		return false
	}
	
	new stats[8],bh[8]
	get_user_wstats(id,wpn_id,stats,bh)
	
	set_array(3,stats,STATS_END)
	set_array(4,bh,HIT_END)
	
	return (stats[STATS_DEATHS] || stats[STATS_SHOTS])
}

/*
* ���������� �� ������� �����
*
* native get_user_wrstats(index, wpnindex, stats[8], bodyhits[8])
*/
public native_get_user_wrstats(plugin_id,params)
{
	new id = get_param(1)
	
	if(!(0 < id <= MaxClients))	// ������� ����� ���� ������
	{
		log_error(AMX_ERR_NATIVE,"Player index out of bounds (%d)",id)
		
		return false
	}
	
	new wpn_id = get_param(2)
	
	if(wpn_id != 0 && !(0 < wpn_id < MAX_WEAPONS))
	{
		log_error(AMX_ERR_NATIVE,"Weapon index out of bounds (%d)",id)
		
		return false
	}
	
	new stats[8],bh[8]
	get_user_wrstats(id,wpn_id,stats,bh)
	
	set_array(3,stats,STATS_END)
	set_array(4,bh,HIT_END)
	
	return (stats[STATS_DEATHS] || stats[STATS_SHOTS])
}


/*
* ��������� ���������� ������
*
* native get_user_stats(index, stats[8], bodyhits[8])
*/
public native_get_user_stats(plugin_id,params)
{
	new id = get_param(1)
	
	if(!(0 < id <= MaxClients))	// ������� ����� ���� ������
	{
		log_error(AMX_ERR_NATIVE,"Player index out of bounds (%d)",id)
		
		return 0
	}
	
	if(player_data[id][PLAYER_LOADSTATE] < LOAD_OK) // ������ �����������
	{
		return 0
	}
	
	set_array(2,player_data[id][PLAYER_STATS],8)
	set_array(3,player_data[id][PLAYER_HITS],8)
	
	return player_data[id][PLAYER_RANK]
}

/*
* ���������� �� ������� �����
*
* native get_user_rstats(index, stats[8], bodyhits[8])
*/
public native_get_user_rstats(plugin_id,params)
{
	new id = get_param(1)
	
	if(!(0 < id <= MaxClients))	// ������� ����� ���� ������
	{
		log_error(AMX_ERR_NATIVE,"Player index out of bounds (%d)",id)
		
		return false
	}
	
	new stats[8],bh[8]
	get_user_rstats(id,stats,bh)
	
	set_array(2,stats,STATS_END)
	set_array(3,bh,HIT_END)
	
	return (stats[STATS_DEATHS] || stats[STATS_SHOTS])
}
/*
* ���������� �� �������
*
* native get_user_vstats(index, victim, stats[8], bodyhits[8], wpnname[] = "", len = 0);
*/
public native_get_user_vstats(plugin_id,params)
{
	if(params != 6)
	{
		log_error(AMX_ERR_NATIVE,"Bad arguments num, expected 6, passed %d",params)
		
		return false
	}
	
	new id = get_param(1)
	new victim = get_param(2)
	
	if(!(0 < id <= MaxClients) || (victim != 0 && !(0 < victim <= MaxClients)))	// ������� ����� ���� ������
	{
		log_error(AMX_ERR_NATIVE,"Player index out of bounds (%d/%d)",id,victim)
		
		return false
	}
	
	set_array(3,player_vstats[id][victim],STATS_END)
	set_array(4,player_vhits[id][victim],HIT_END)
	set_string(5,player_vwname[id][victim],get_param(6))
	
	return (player_vstats[id][victim][STATS_KILLS] || player_vstats[id][victim][STATS_HITS])
}

/*
* ���������� �� ������
*
* native get_user_astats(index, victim, stats[8], bodyhits[8], wpnname[] = "", len = 0);
*/
public native_get_user_astats(plugin_id,params)
{
	if(params != 6)
	{
		log_error(AMX_ERR_NATIVE,"Bad arguments num, expected 6, passed %d",params)
		
		return false
	}
	
	new id = get_param(1)
	new attacker = get_param(2)
	
	if(!(0 < id <= MaxClients) || (attacker != 0 && !(0 < attacker <= MaxClients)))	// ������� ����� ���� ������
	{
		log_error(AMX_ERR_NATIVE,"Player index out of bounds (%d/%d)",id,attacker)
		
		return false
	}
	
	set_array(3,player_astats[id][attacker],STATS_END)
	set_array(4,player_ahits[id][attacker],HIT_END)
	set_string(5,player_awname[id][attacker],get_param(6))
	
	return (player_astats[id][attacker][STATS_KILLS] || player_astats[id][attacker][STATS_HITS])
}

public native_reset_user_wstats()
{
	new id = get_param(1)
	
	if(!(0 < id <= MaxClients))	// ������� ����� ���� ������
	{
		log_error(AMX_ERR_NATIVE,"Player index out of bounds (%d)",id)
		
		return false
	}
	
	return reset_user_wstats(id)
}

/*
* ���������� ����� ���������� ������� � ���� ������
*
* native get_statsnum()
*/
public native_get_statsnum(plugin_id,params)
{
	return statsnum
}

/*
* ��������� ��������� �� �������
*
* native get_stats(index, stats[8], bodyhits[8], name[], len, authid[] = "", authidlen = 0);
*/
public native_get_stats(plugin_id,params)
{
	new index = get_param(1)	// ������ � ����������
	
	// �����������
	new index_str[10],stats_cache[stats_cache_struct]
	num_to_str(index,index_str,charsmax(index_str))
	
	// ���� ���������� � ����
	if(stats_cache_trie && TrieGetArray(stats_cache_trie,index_str,stats_cache,stats_cache_struct))
	{
		set_array(2,stats_cache[CACHE_STATS],sizeof stats_cache[CACHE_STATS])
		set_array(3,stats_cache[CACHE_HITS],sizeof stats_cache[CACHE_HITS])
		set_string(4,stats_cache[CACHE_NAME],get_param(5))
		
		// TODO: ������� ���������
		if(params > 5)
		{
			set_string(6,stats_cache[CACHE_STEAMID],get_param(7))
		}
		
		return !stats_cache[CACHE_LAST] ? index + 1 : 0
	}
	// �����������
	
	// ��������� ���������� � �� ��� ��������� ���������� ������
	// TODO: ��������� �������
	if(!DB_OpenConnection())
	{
		return false	// ������ �������� ����������
	}
	else
	{
		// ������� �� ����� ����������
		// ����� �� ��������� ����� � ������ �������� ����� ��������� ������ �� ���� ����������
		if(!task_exists(task_confin))
		{
			set_task(0.1,"DB_CloseConnection",task_confin)
		}
	}
	
	new query[QUERY_LENGTH],len
	
	// ������ ������
	len += formatex(query[len],charsmax(query)-len,"SELECT ")
	
	// ����� ���������� (��, � ������� ���� � ���������� ������ ����)
	for(new i = ROW_STEAMID ; i <= ROW_DMG ; i++)
	{
		len += formatex(query[len],charsmax(query)-len,"%s`%s`",
			i == ROW_STEAMID ? "" : ",",
			row_names[i]
		)
	}
	
	// ��������� xml ��������� ���������
	for(new i ; i < sizeof player_data[][PLAYER_HITS] ; i++)
	{
		len += formatex(query[len],charsmax(query)-len,",ExtractValue(`%s`,'//i[%d]')",
			row_names[ROW_HITSARRAY],i + 1
		)
	}
	
	// ������ �� ����
	len += formatex(query[len],charsmax(query)-len,",(")
	len += get_score_sql(query[len],charsmax(query)-len)
	len += formatex(query[len],charsmax(query)-len,") as `rank`")
	
	// ����������� ��������� ������
	// ���� ����, �� ���������� ������� index + 1
	len += formatex(query[len],charsmax(query)-len," FROM `csstats` as `a` ORDER BY `rank` LIMIT %d,2",
		index
	)
	
	new Handle:sqlQue = SQL_PrepareQuery(sql_con,query)
	
	cnt_nthd ++
	
	if(!SQL_Execute(sqlQue))
	{
		new errNum,err[256]
		errNum = SQL_QueryError(sqlQue,err,charsmax(err))
		
		log_amx("MySQL query failed")
		log_amx("[ %d ] %s",errNum,err)
		log_amx("[ SQL ] %s",query)
		
		SQL_FreeHandle(sqlQue)
		
		cnt_fail ++
		
		return 0
	}
	
	if(SQL_NumResults(sqlQue))
	{
		new name[32],steamid[30],stats[8],hits[8]
		
		SQL_ReadResult(sqlQue,0,steamid,charsmax(steamid))
		SQL_ReadResult(sqlQue,1,name,charsmax(name))
		
		// ������ ������ (��, ��� ����� ���� � ����� ��� ����� ����)
		for(new i = 2; i < sizeof player_data[][PLAYER_STATS] +  sizeof player_data[][PLAYER_HITS] + 2 ; i++)
		{
			// ������� ���������
			if(i - 2 < sizeof player_data[][PLAYER_STATS])
				stats[i - 2] = SQL_ReadResult(sqlQue,i)
			else // ���������� ���������
				hits[i - sizeof player_data[][PLAYER_STATS] - 2] = SQL_ReadResult(sqlQue,i)
		}
		
		set_array(2,stats,sizeof player_data[][PLAYER_STATS])
		set_array(3,hits,sizeof player_data[][PLAYER_HITS])
		set_string(4,name,get_param(5))
		
		// TODO: ������� ���������
		if(params > 5)
		{
			set_string(6,steamid,get_param(7))
		}
		
		// ����������� ������
		if(!stats_cache_trie)
		{
			stats_cache_trie = TrieCreate()
		}
		
		copy(stats_cache[CACHE_NAME],charsmax(stats_cache[CACHE_NAME]),name)
		copy(stats_cache[CACHE_STEAMID],charsmax(stats_cache[CACHE_STEAMID]),steamid)
		arraycopy(stats_cache[CACHE_STATS],stats)
		arraycopy(stats_cache[CACHE_HITS],hits)
		stats_cache[CACHE_LAST] = SQL_NumResults(sqlQue) <= 1
		
		TrieSetArray(stats_cache_trie,index_str,stats_cache,stats_cache_struct)
		// ����������� ������
		
		return SQL_NumResults(sqlQue) > 1 ? index + 1 : 0
	}
	
	SQL_FreeHandle(sqlQue)
	
	return 0
}

public DB_OpenConnection()
{
	if(sql_con != Empty_Handle)
	{
		return true
	}
	
	new errNum,err[256]
	sql_con = SQL_Connect(sql,errNum,err,charsmax(err))
	
	cnt_int ++
	
	if(errNum)
	{
		log_amx("MySQL query failed")
		log_amx("[ %d ] %s",errNum,err)
			
		return false
	}
	
	log_amx("--> sql connection open %.2f",get_gametime())
	
	return true
}

public DB_CloseConnection()
{
	if(sql_con != Empty_Handle)
	{
		SQL_FreeHandle(sql_con)
		sql_con = Empty_Handle
		
		log_amx("--> sql connection closed %.2f",get_gametime())
	}
}

// TODO: ������ get_stats
public native_get_user_stats2(plugin_id,params)
{
	return 0
}

public native_get_stats2(plugin_id,params)
{
	return 0
}

public plugin_end()
{
	log_amx("--> mysql stats:")
	log_amx("--> THREADED QUERIES: %d",cnt_thd)
	log_amx("--> NON-THREADED QUERIES: %d",cnt_nthd)
	log_amx("--> FAIL QUERIES: %d",cnt_fail)
	log_amx("--> CONNECTIONS: %d",cnt_int)
}

/*
* �������� ���������� ������ �� ���� ������
*/
DB_LoadPlayerData(id)
{
	new name[96],steamid[30],ip[16]
	
	// ������ ���, ��, ���� ������
	//get_user_name(id,name,charsmax(name))
	get_user_info(id,"name",name,charsmax(name))
	get_user_authid(id,steamid,charsmax(steamid))
	get_user_ip(id,ip,charsmax(ip),true)
	
	mysql_escape_string(name,charsmax(name))
	
	// ��������� SQL ������
	new query[QUERY_LENGTH],len,sql_data[2]
	
	sql_data[0] = SQL_LOAD
	sql_data[1] = id
	player_data[id][PLAYER_LOADSTATE] = LOAD_WAIT
	
	len += formatex(query[len],charsmax(query)-len,"SELECT *,(")
	len += get_score_sql(query[len],charsmax(query)-len)
	len += formatex(query[len],charsmax(query)-len,"),(")
	len += get_statsnum_sql(query[len],charsmax(query)-len)
	len += formatex(query[len],charsmax(query)-len,")")
	
	// ��������� xml ��������� ���������
	for(new i ; i < sizeof player_data[][PLAYER_HITS] ; i++)
	{
		len += formatex(query[len],charsmax(query)-len,",ExtractValue(`%s`,'//i[%d]')",
			row_names[ROW_HITSARRAY],i + 1
		)
	}
	
	
	switch(get_pcvar_num(track_set))
	{
		case 0: // ���������� �� ����
		{
			len += formatex(query[len],charsmax(query)-len," FROM `csstats` AS `a` WHERE `name` = '%s'",
				name
			)
		}
		case 1: // ���������� �� steamid
		{
			len += formatex(query[len],charsmax(query)-len," FROM `csstats` AS `a` WHERE `steamid` = '%s'",
				steamid
			)
		}
		case 2: // ���������� �� ip
		{
			len += formatex(query[len],charsmax(query)-len," FROM `csstats` AS `a` WHERE `ip` = '%s'",
				ip
			)
		}
		default:
		{
			return false
		}
	}
	
	// �������� ���������� �������
	SQL_ThreadQuery(sql,"SQL_Handler",query,sql_data,sizeof sql_data)
	
	return true
}


/*
* ���������� ���������� ������
*/
DB_SavePlayerData(id,bool:reload = false)
{
	if(player_data[id][PLAYER_LOADSTATE] < LOAD_OK) // ����� �� ����������
	{
		return false
	}
	
	new name[96],steamid[30],ip[16],query[QUERY_LENGTH],i
	
	new sql_data[2 + 					// 2
		sizeof player_data[][PLAYER_STATS] + // 8
		sizeof player_data[][PLAYER_HITS] // 8
	]
	
	sql_data[1] = id
	
	// ������ ���, ��, ���� ������
	//get_user_name(id,name,charsmax(name))
	get_user_info(id,"name",name,charsmax(name))
	get_user_authid(id,steamid,charsmax(steamid))
	get_user_ip(id,ip,charsmax(ip),true)
	
	mysql_escape_string(name,charsmax(name))
	
	new stats[8],stats2[4],hits[8]
	get_user_wstats(id,0,stats,hits)
	get_user_stats2(id,stats2)
	
	new hits_xml[256],xml_len
	
	/*if(!stats[STATS_DEATHS] && !stats[STATS_SHOTS])
	{
		return false
	}*/
	
	switch(player_data[id][PLAYER_LOADSTATE])
	{
		case LOAD_OK: // ���������� ������
		{
			if(reload)
			{
				player_data[id][PLAYER_LOADSTATE] = LOAD_UPDATE
			}
			
			sql_data[0] = SQL_UPDATE
			
			new diffstats[sizeof player_data[][PLAYER_STATS]]
			new diffstats2[sizeof player_data[][PLAYER_STATS2]]
			new diffhits[sizeof player_data[][PLAYER_HITS]]
			new len,to_save
			
			len += formatex(query[len],charsmax(query) - len,"UPDATE `csstats` SET")
			
			// ��������� �� ������� � ����������� �������
			for(i = 0 ; i < sizeof player_data[][PLAYER_STATS] ; i++)
			{
				diffstats[i] = stats[i] - player_data[id][PLAYER_STATSLAST][i] // ������ �������
				player_data[id][PLAYER_STATSLAST][i] = stats[i]
				
				if(diffstats[i])
				{
					len += formatex(query[len],charsmax(query) - len,"%s`%s` = `%s` + '%d'",
						!to_save ? " " : ",",
						row_names[i + ROW_KILLS],
						row_names[i + ROW_KILLS],
						diffstats[i]
					)
					
					to_save ++
				}
			}
			
			// ��������� �� ������� � ����������� �������
			for(i = 0 ; i < sizeof player_data[][PLAYER_STATS2] ; i++)
			{
				diffstats2[i] = stats2[i] - player_data[id][PLAYER_STATS2LAST][i] // ������ �������
				player_data[id][PLAYER_STATS2LAST][i] = stats2[i]
				
				if(diffstats[i])
				{
					len += formatex(query[len],charsmax(query) - len,"%s`%s` = `%s` + '%d'",
						!to_save ? " " : ",",
						row_names[i + ROW_BOMBDEF],
						row_names[i + ROW_BOMBDEF],
						diffstats2[i]
					)
					
					to_save ++
				}
			}
			
			if(to_save)
			{
				// �������� ��� � ��������, ������� ���������� ������� �� ������� ���
				for(i = 0,xml_len = 0 ; i < sizeof player_data[][PLAYER_HITS] ; i++)
				{
					diffhits[i] = hits[i] - player_data[id][PLAYER_HITSLAST][i] // ������ �������
					player_data[id][PLAYER_HITSLAST][i] = hits[i]
					
					xml_len += formatex(hits_xml[xml_len],charsmax(hits_xml) - xml_len,"<i>%d</i>",diffhits[i])
				}
				
				len += formatex(query[len],charsmax(query) - len,",`%s` = '%s'",
					row_names[ROW_HITSARRAY],hits_xml
				)
			}
			
			len += formatex(query[len],charsmax(query) - len,",`last_join` = CURRENT_TIMESTAMP() WHERE `%s` = '%d'",
				row_names[ROW_ID],player_data[id][PLAYER_ID]
			)
			
			if(!to_save) // ������ ���������
			{
				if(player_data[id][PLAYER_LOADSTATE] == LOAD_UPDATE)
				{
					player_data[id][PLAYER_LOADSTATE] = LOAD_NO
					DB_LoadPlayerData(id)
				}
				
				return false
			}
			
			// stats
			for(i = 0 ; i < sizeof player_data[][PLAYER_STATS] ; i++)
			{
				sql_data[i + 2] = diffstats[i]
			}
			
			// hits
			for(i = 0 ; i < sizeof player_data[][PLAYER_HITS] ; i++)
			{
				sql_data[i + 2 + sizeof player_data[][PLAYER_STATS]] = diffhits[i]
			}
			
			
		}
		case LOAD_NEW: // ������ �� ���������� ����� ������
		{
			// ������ xml ��� ���������� ���������
			for(i = 0,xml_len = 0 ; i < sizeof player_data[][PLAYER_HITS];i++)
			{
				xml_len += formatex(hits_xml[xml_len],charsmax(hits_xml) - xml_len,"<i>%d</i>",player_data[id][PLAYER_HITS])
			}
			
			sql_data[0] = SQL_INSERT
			
			formatex(query,charsmax(query),"INSERT INTO `csstats` \
							(`%s`,`%s`,`%s`,`%s`,`%s`,`%s`,`%s`,`%s`,`%s`,`%s`,`%s`,`%s`,`%s`,`%s`,`%s`)\
							VALUES('%s','%s','%s','%d','%d','%d','%d','%d','%d','%d','%s','%d','%d','%d','%d')\
							",
							
					row_names[ROW_STEAMID],
					row_names[ROW_NAME],
					row_names[ROW_IP],
					row_names[ROW_KILLS],
					row_names[ROW_DEATHS],
					row_names[ROW_HS],
					row_names[ROW_TKS],
					row_names[ROW_SHOTS],
					row_names[ROW_HITS],
					row_names[ROW_DMG],
					row_names[ROW_HITSARRAY],
					row_names[ROW_BOMBDEF],
					row_names[ROW_BOMBDEFUSED],
					row_names[ROW_BOMBPLANTS],
					row_names[ROW_BOMBEXPLOSIONS],
					
					steamid,name,ip,
					
					stats[STATS_KILLS] - player_data[id][PLAYER_STATSLAST][STATS_KILLS],
					stats[STATS_DEATHS] - player_data[id][PLAYER_STATSLAST][STATS_DEATHS],
					stats[STATS_HS] - player_data[id][PLAYER_STATSLAST][STATS_HS],
					stats[STATS_TK] - player_data[id][PLAYER_STATSLAST][STATS_TK],
					stats[STATS_SHOTS] - player_data[id][PLAYER_STATSLAST][STATS_SHOTS],
					stats[STATS_HITS] - player_data[id][PLAYER_STATSLAST][STATS_HITS],
					stats[STATS_DMG] - player_data[id][PLAYER_STATSLAST][STATS_DMG],
					
					hits_xml,
					
					stats2[STATS2_DEFAT] - player_data[id][PLAYER_STATS2LAST][STATS2_DEFAT],
					stats2[STATS2_DEFOK] - player_data[id][PLAYER_STATS2LAST][STATS2_DEFOK],
					stats2[STATS2_PLAAT] - player_data[id][PLAYER_STATS2LAST][STATS2_PLAAT],
					stats2[STATS2_PLAOK] - player_data[id][PLAYER_STATS2LAST][STATS2_PLAOK]
			)
			
			// stats
			for(i = 0 ; i < sizeof player_data[][PLAYER_STATS] ; i++)
			{
				sql_data[i + 2] = stats[i]
			}
			
			// hits
			for(i = 0 ; i < sizeof player_data[][PLAYER_HITS] ; i++)
			{
				sql_data[i + 2 + sizeof player_data[][PLAYER_STATS]] = hits[i]
			}
			
			if(reload)
			{
				player_data[id][PLAYER_LOADSTATE] = LOAD_UPDATE
			}
		}
	}
	
	if(query[0])
	{
		SQL_ThreadQuery(sql,"SQL_Handler",query,sql_data,sizeof sql_data)
	}
	
	return true
}

/*
* ��������� ����� ������� � ���� �������
*/
public DB_GetPlayerRanks()
{
	new players[32],pnum
	get_players(players,pnum)
	
	new query[QUERY_LENGTH],len
	
	// ������ SQL ������
	len += formatex(query[len],charsmax(query) - len,"SELECT `id`,(")
	len += get_score_sql(query[len],charsmax(query) - len)
	len += formatex(query[len],charsmax(query) - len,") FROM `csstats` as `a` WHERE `id` IN(")
	
	new bool:letsgo
	
	for(new i,player,bool:y  ; i < pnum ; i++)
	{
		player = players[i]
		
		if(player_data[player][PLAYER_ID])
		{
			len += formatex(query[len],charsmax(query) - len,"%s'%d'",y ? "," : "",player_data[player][PLAYER_ID])
			y = true
			letsgo = true
		}
	}
	
	len += formatex(query[len],charsmax(query) - len,")")
	
	if(letsgo)
	{
		new data[1] = SQL_UPDATERANK
		SQL_ThreadQuery(sql,"SQL_Handler",query,data,sizeof data)
	}
}

/*
* ���������� ���������� ���� �������
*/
public DB_SaveAll()
{
	new players[32],pnum
	get_players(players,pnum)
	
	for(new i ; i < pnum ; i++)
	{
		DB_SavePlayerData(players[i])
	}
}

/*
* ��������� ��� ��� get_stats
*/
Cache_Stats_Update()
{
	if(!stats_cache_trie)
		return false
	
	TrieClear(stats_cache_trie)
	
	return true
}

/*
* ��������� ������� �� SQL �������
*/
public SQL_Handler(failstate,Handle:sqlQue,err[],errNum,data[],dataSize){
	// ���� ������
	switch(failstate)
	{
		case TQUERY_CONNECT_FAILED:  // ������ ���������� � mysql ��������
		{
			log_amx("MySQL connection failed")
			log_amx("[ %d ] %s",errNum,err)
			
			cnt_fail ++

			return PLUGIN_HANDLED
		}
		case TQUERY_QUERY_FAILED:  // ������ SQL �������
		{
			new lastQue[QUERY_LENGTH]
			SQL_GetQueryString(sqlQue,lastQue,charsmax(lastQue)) // ������ ��������� SQL ������
			
			log_amx("MySQL query failed")
			log_amx("[ %d ] %s",errNum,err)
			log_amx("[ SQL ] %s",lastQue)
			
			cnt_fail ++
			
			return PLUGIN_HANDLED
		}
	}
	
	cnt_thd ++
	

	switch(data[0])
	{
		case SQL_LOAD: // �������� ���������� ������
		{
			new id = data[1]
		
			log_amx("--> load report: [%d] [%d] [%.2f]",id,is_user_connected(id),get_gametime())
		
			if(!is_user_connected(id))
			{
				return PLUGIN_HANDLED
			}
			
			if(SQL_NumResults(sqlQue)) // ��������� ����������
			{
				player_data[id][PLAYER_LOADSTATE] = LOAD_OK
				player_data[id][PLAYER_ID] = SQL_ReadResult(sqlQue,ROW_ID)
				
				// ����� ����������
				player_data[id][PLAYER_STATS][STATS_KILLS] = SQL_ReadResult(sqlQue,ROW_KILLS)
				player_data[id][PLAYER_STATS][STATS_DEATHS] = SQL_ReadResult(sqlQue,ROW_DEATHS)
				player_data[id][PLAYER_STATS][STATS_HS] = SQL_ReadResult(sqlQue,ROW_HS)
				player_data[id][PLAYER_STATS][STATS_TK] = SQL_ReadResult(sqlQue,ROW_TKS)
				player_data[id][PLAYER_STATS][STATS_SHOTS] = SQL_ReadResult(sqlQue,ROW_SHOTS)
				player_data[id][PLAYER_STATS][STATS_HITS] = SQL_ReadResult(sqlQue,ROW_HITS)
				player_data[id][PLAYER_STATS][STATS_DMG] = SQL_ReadResult(sqlQue,ROW_DMG)
				
				// ���������� cstrike
				player_data[id][PLAYER_STATS2][STATS2_DEFAT] = SQL_ReadResult(sqlQue,ROW_BOMBDEF)
				player_data[id][PLAYER_STATS2][STATS2_DEFOK] = SQL_ReadResult(sqlQue,ROW_BOMBDEFUSED)
				player_data[id][PLAYER_STATS2][STATS2_PLAAT] = SQL_ReadResult(sqlQue,ROW_BOMBPLANTS)
				player_data[id][PLAYER_STATS2][STATS2_PLAOK] = SQL_ReadResult(sqlQue,ROW_BOMBEXPLOSIONS)
				
				// ���. �������
				player_data[id][PLAYER_RANK] = SQL_ReadResult(sqlQue,row_ids)	// ���� ������
				statsnum = SQL_ReadResult(sqlQue,row_ids + 1)			// ����� ���-�� ������� � ��
				
				// ���������� ���������
				for(new i ; i < sizeof player_data[][PLAYER_HITS] ; i++)
				{
					player_data[id][PLAYER_HITS][i] = SQL_ReadResult(sqlQue,row_ids + 2 + i)
				}
				
				log_amx("--> load ok! %d, rank: %d of %d [%.2f]",player_data[id][PLAYER_ID],player_data[id][PLAYER_RANK],statsnum,get_gametime())
			}
			else // �������� ��� ������ ������
			{
				player_data[id][PLAYER_LOADSTATE] = LOAD_NEW
				
				DB_SavePlayerData(id) // ��������� ������ � ���� ������
				log_amx("--> load new %d! [%.2f]",id,get_gametime())
			}
		}
		case SQL_INSERT:	// ������ ����� ������
		{
			new id = data[1]
			
			if(is_user_connected(id))
			{
				if(player_data[id][PLAYER_LOADSTATE] == LOAD_UPDATE)
				{
					player_data[id][PLAYER_LOADSTATE] = LOAD_NO
					DB_LoadPlayerData(id)
					
					return PLUGIN_HANDLED
				}
				
				player_data[id][PLAYER_ID] = SQL_GetInsertId(sqlQue)	// ��������� ����
				player_data[id][PLAYER_LOADSTATE] = LOAD_OK		// ������ ���������
				
				
				// � ������ 0)0)0
				
				// ���������� ����������
				for(new i ; i < sizeof player_data[][PLAYER_STATS] ; i++)
				{
					player_data[id][PLAYER_STATS][i] = data[2 + i]
				}
				
				// ���������� �� ����������
				for(new i ; i < sizeof player_data[][PLAYER_HITS] ; i++)
				{
					player_data[id][PLAYER_HITS][i] = data[2 + i + sizeof player_data[][PLAYER_STATS]]
				}
				
				// ��������� ������� ������ ���-�� �������
				statsnum++
			}
			
			// ��������� ������ �������
			// �������� � ���������, ���-�� ������ ��������� ��� ������������� ���������� ������
			if(!task_exists(task_rankupdate))
			{
				set_task(1.0,"DB_GetPlayerRanks",task_rankupdate)
			}
		}
		case SQL_UPDATE: // ���������� ������
		{
			new id = data[1]
			
			if(is_user_connected(id))
			{	
				// ���������� ����������
				for(new i ; i < sizeof player_data[][PLAYER_STATS] ; i++)
				{
					player_data[id][PLAYER_STATS][i] += data[2 + i]
				}
				
				// ���������� ����������
				for(new i ; i < sizeof player_data[][PLAYER_HITS] ; i++)
				{
					player_data[id][PLAYER_HITS][i] += data[2 + i + sizeof player_data[][PLAYER_STATS]]
				}
				
				if(player_data[id][PLAYER_LOADSTATE] == LOAD_UPDATE)
				{
					player_data[id][PLAYER_LOADSTATE] = LOAD_NO
					DB_LoadPlayerData(id)
				}
			}
			
			// ��������� ������ �������
			// �������� � ���������, ���-�� ������ ��������� ��� ������������� ���������� ������
			if(!task_exists(task_rankupdate))
			{
				set_task(0.1,"DB_GetPlayerRanks",task_rankupdate)
			}
		}
		case SQL_UPDATERANK:
		{
			while(SQL_MoreResults(sqlQue))
			{
				new pK =  SQL_ReadResult(sqlQue,0)
				new rank = SQL_ReadResult(sqlQue,1)
				
				for(new i ; i < MAX_PLAYERS ; i++)
				{
					if(player_data[i][PLAYER_ID] == pK)	// ������ ���� �� ���������� �����
					{
						player_data[i][PLAYER_RANK] = rank
					}
				}
				
				SQL_NextRow(sqlQue)
			}
			
			Cache_Stats_Update()
		}
	}

	return PLUGIN_HANDLED
}

/*
* ������ �� ������� �����
*/
get_score_sql(sql_que[] = "",sql_que_len = 0)
{
	// ����������� ������� csstats (��������-������-tk)
	return formatex(sql_que,sql_que_len,"SELECT COUNT(*) FROM csstats WHERE (kills-deaths-tks)>=(a.kills-a.deaths-a.tks)")
}

/*
* ������ �� ����� ���-�� ������� � ��
*/ 
get_statsnum_sql(sql_que[] = "",sql_que_len = 0)
{
	return formatex(sql_que,sql_que_len,"SELECT COUNT(*) FROM csstats WHERE 1")
}

/*********    mysql escape functions     ************/
mysql_escape_string(dest[],len)
{
	//copy(dest, len, source);
	replace_all(dest,len,"\\","\\\\");
	replace_all(dest,len,"\0","\\0");
	replace_all(dest,len,"\n","\\n");
	replace_all(dest,len,"\r","\\r");
	replace_all(dest,len,"\x1a","\Z");
	replace_all(dest,len,"'","\'");
	replace_all(dest,len,"^"","\^"");
}

stock arraycopy( any:into[], any:from[], len = sizeof into, bool:ignoretags = false, intotag = tagof into, intosize = sizeof into, intopos = 0, fromtag = tagof from, fromsize = sizeof from, frompos = 0) {
    if (!ignoretags && intotag != fromtag) {
        //So we know no elements were copied (we did not remove an element ie. returning -1)
        return 0;
    }
    
    new i
    while (i < len) {
        if (intopos >= intosize || frompos >= fromsize) {
            break;
        }
        
        into[intopos++] = from[frompos++];
        i++;
    }
    
    return i;
}
