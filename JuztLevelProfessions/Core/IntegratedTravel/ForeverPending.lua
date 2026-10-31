local _, JLP = ...
local T = JLP._integratedTravel
-- Source-backed connectivity research only, NOT routable navigation data.
-- Other corridors remain non-routable research. The OG/UC corridor moved into
-- HordeOrgrimmarUndercity.lua as source-supported alpha2 data; still requires client QA.
T.PendingTransportReferences={
    {from='Undercity',to="Gromgol",mode='ZEPPELIN',faction='HORDE',
     reference='https://www.curseforge.com/wow/addons/forever-transit',
     status='REQUIRES_INGAME_NODE_COORDINATES_AND_ACCESS_VERIFICATION'},
    {from='Orgrimmar',to="Gromgol",mode='ZEPPELIN',faction='HORDE',
     reference='https://www.curseforge.com/wow/addons/forever-transit',
     status='REQUIRES_INGAME_NODE_COORDINATES_AND_ACCESS_VERIFICATION'},
}
