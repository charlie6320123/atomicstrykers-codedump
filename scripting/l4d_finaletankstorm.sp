#include <sourcemod>
#include <sdktools>
#define DEBUG 0

#define PLUGIN_VERSION "1.0.1"
#define PLUGIN_NAME "L4D Finale Tankstorm"

new Handle:SetTankAmount = INVALID_HANDLE;
new Handle:HealthDecrease = INVALID_HANDLE;
new Handle:hMaxZombies = INVALID_HANDLE;
new bool:HasHealthReduced[MAXPLAYERS+1];
new bool:bIsFinale = false;
new DefaultMaxZombies;

public Plugin:myinfo = {
	name = PLUGIN_NAME,
	author = " AtomicStryker ",
	description = " Spawns X weaker Tanks instead of a single one during Finale waves ",
	version = PLUGIN_VERSION,
	url = ""
};

public OnPluginStart()
{
	HookEvent("player_death", Event_PlayerDeath, EventHookMode_Pre);
	
	SetTankAmount = CreateConVar("l4d_finaletankstorm_tankcount","3"," How many tanks shall spawn ", FCVAR_PLUGIN|FCVAR_SPONLY|FCVAR_NOTIFY, true, 3.0, true, 8.0);
	HealthDecrease = CreateConVar("l4d_finaletankstorm_hpsetting","0.40"," How much Health each of the X Tanks have compared to a standard one. '1.0' would be full health ", FCVAR_PLUGIN|FCVAR_SPONLY|FCVAR_NOTIFY, true, 0.01, true, 1.00);
	CreateConVar("l4d_finaletankstorm_version", PLUGIN_VERSION, " Version of L4D Finale Tank Storm on this server ", FCVAR_PLUGIN|FCVAR_SPONLY|FCVAR_NOTIFY|FCVAR_DONTRECORD);
	
	AutoExecConfig(true, "l4d_finaletankstorm");
	
	hMaxZombies = FindConVar("z_max_player_zombies")
	DefaultMaxZombies = GetConVarInt(hMaxZombies);
	
	HookEvent("finale_start", FinaleBegins);
	HookEvent("round_end", RoundEnd);
}

public OnMapStart()
{
	SetConVarInt(hMaxZombies, DefaultMaxZombies);
	ResetBool();
}

public OnMapEnd()
{
	SetConVarInt(hMaxZombies, DefaultMaxZombies);
	ResetBool();
}

public Action:RoundEnd(Handle:event, const String:name[], bool:dontBroadcast)
{
	bIsFinale = false;
	ResetBool();
}


public ResetBool()
{
	for (new i=1 ; i<=MaxClients ; i++)
	{
		HasHealthReduced[i] = false;
	}
}

public OnClientAuthorized(client, const String:auth[]) // this catches Tank Spawns the game does by itself, and only these
{
	if (!IsFakeClient(client)) return;
	decl String:name[256];
	GetClientName(client, name, sizeof(name));
	if (StrEqual(name, "Tank") && CountTanks() == 0 ) GameTankSpawned(client); // ive added the counttanks check for the "more tanks that human slots" situation
}

static GameTankSpawned(any:client)
{
	if(!bIsFinale)
	{
		#if DEBUG
		PrintToChatAll("\x04[Finale Tank Storm Plugin] \x01Its not a Finale yet");
		#endif
		
		return;
	}
	
	ReduceTankHealth(client);
	
	new Float:TankDelay = GetConVarFloat(FindConVar("director_tank_lottery_selection_time")) + 2.0;  
	// this to avoid 'disappearing' tanks. After Lottery strange things happen
	
	CreateTimer(TankDelay, SpawnMoreTanks, client);
	
	SetConVarInt(hMaxZombies, DefaultMaxZombies + GetConVarInt(SetTankAmount));
	// this to avoid other tank related oddities. We silently raise max Infected count before spawning another tank	
	
	#if DEBUG
	PrintToChatAll("\x04[Finale Tank Storm Plugin] \x01Spawning Another Tank with Delay %f!", TankDelay);
	#endif
}

public Action:SpawnMoreTanks(Handle:timer, any:client)
{
	if (client == 0 || !IsClientConnected(client)) // If this was the Bot Tank Client which has left the game already, or else false
	{
		#if DEBUG
		PrintToChatAll("\x04[Finale Tank Storm Plugin] \x01Event Client was found invalid, finding a new one!");
		#endif
		
		for (new i = 1; i <= MaxClients; i++)
		{
			if (IsClientConnected(i) && IsClientInGame(i))
			{
				client = i
				break;
			}
		}
	}
	
	if (CountTanks()+1 > GetConVarInt(SetTankAmount)) return;
	
	PrintToChatAll("\x04[Finale Tank Storm Plugin] \x01Spawning %i. of %i Tanks with %i percent Health each!", CountTanks()+1, GetConVarInt(SetTankAmount), RoundFloat(100*GetConVarFloat(HealthDecrease)));

	new flags = GetCommandFlags("z_spawn");
	SetCommandFlags("z_spawn", flags & ~FCVAR_CHEAT);
	FakeClientCommand(client, "z_spawn tank auto")
	SetCommandFlags("z_spawn", flags);
	
	CreateTimer(3.0, CheckSpawn, 0);
}

public Action:CheckSpawn(Handle:timer)
{
	if (CountTanks() < GetConVarInt(SetTankAmount))
	{
		#if DEBUG
		PrintToChatAll("\x04[Finale Tank Storm Plugin] \x01We require more Tanks, spawning another!");
		#endif
		
		CreateTimer(0.5, SpawnMoreTanks, 0);
	}
}

public Action:FinaleBegins(Handle:event, const String:name[], bool:dontBroadcast)
{
	bIsFinale = true;
	DefaultMaxZombies = GetConVarInt(hMaxZombies);
	PrintToChatAll("\x04[Finale Tank Storm Plugin] \x01Finale begins!");
	ResetBool();
}

public Action:Event_PlayerDeath (Handle:event, const String:name[], bool:dontBroadcast)
{
	if(!bIsFinale) return Plugin_Continue;
	new client = GetClientOfUserId(GetEventInt(event,"userid"));
	if (client == 0) return Plugin_Continue;
	
	decl String:stringclass[32];
	GetClientModel(client, stringclass, 32);
	
	if (StrContains(stringclass, "hulk", false) != -1)
	{
		HasHealthReduced[client] = false;
		CreateTimer(3.0, PrintLivingTanks, client);
	}
	return Plugin_Continue;
}

public Action:ReduceTankHealth(client)
{
	// This reduces the Tanks Health. Multiple Tanks with full power are ownage ... no wait, they own in any case
	new TankHealth = RoundFloat((GetEntProp(client,Prop_Send,"m_iHealth")*(GetConVarFloat(HealthDecrease))));
	if(TankHealth>65535) TankHealth=65535;
	SetEntProp(client, Prop_Send, "m_iHealth",TankHealth);
	SetEntProp(client, Prop_Send, "m_iMaxHealth",TankHealth);
	HasHealthReduced[client] = true;
}

public Action:PrintLivingTanks(Handle:timer, Handle:client)
{
	new Tanks = CountTanks();
	
	PrintToChatAll("\x03[Double Tank] Tanks left alive: %i", Tanks);
	
	if (Tanks<=0)
	{
		SetConVarInt(hMaxZombies, DefaultMaxZombies);
	}
}

public CountTanks()
{
	new TanksCount = 0;	
	decl String:stringclass[32];
	for (new i=1 ; i<=MaxClients ; i++)
	{
		if (IsClientInGame(i) == true && GetClientHealth(i)>0 && GetClientTeam(i) == 3)
		{
			GetClientModel(i, stringclass, 32);
			if (StrContains(stringclass, "hulk", false) != -1)
			{
				TanksCount++;
				if (!HasHealthReduced[i])
					ReduceTankHealth(i);
			}
		}
	}
	return TanksCount;
}