-- Source-backed preview for Forever 1.60.1. Two-way Classic zeppelin retained by Forever.
-- Platform coordinates originate in the user-provided Travel Options - JuztLevel(1).txt list.
-- The user authorized replacing prior Classic-reference coordinate estimates.
-- These values are not yet player-position verified against each platform in Forever.
-- The term 'verified' on graph edges means source-supported existence, NOT client-tested precision.
local _, JLP = ...
local T = JLP._integratedTravel
local sourceClassic='https://www.wowhead.com/classic/guide/wow-classic-flight-points-zeppelins-boats-travel'
local sourceForever='https://warcraft.wiki.gg/wiki/WoW_Forever'
T.HordeCorridor = {
  contract='juzt-travel-dataset-v1',
  id='horde_og_uc_zeppelin_alpha2',
  sourceBuild='Forever-beta-1.60.1; platform coordinates: user-supplied Travel Options list (2026-10-16)',
  verificationLevel='USER_REFERENCE_NOT_INGAME',
  sources={'Travel Options - JuztLevel(1).txt (user-provided coordinates)',sourceClassic,sourceForever},
  nodes={
    {id='horde_og_uc_durotar',mapID=1411,x=.510,y=.139,
      label='Frezza - south platform to Undercity',zone='Durotar',kind='ZEPPELIN_PLATFORM',
      confirmed=true,provenance='Travel Options - JuztLevel(1).txt (user-provided coordinates)',clientVerified=false},
    {id='horde_uc_og_tirisfal',mapID=1420,x=.606,y=.589,
      label='Zapetta - west platform to Orgrimmar',zone='Tirisfal Glades',kind='ZEPPELIN_PLATFORM',
      confirmed=true,provenance='Travel Options - JuztLevel(1).txt (user-provided coordinates)',clientVerified=false},
  },
  edges={
    {id='horde_zeppelin_og_uc',from='horde_og_uc_durotar',to='horde_uc_og_tirisfal',
      mode='ZEPPELIN',faction='HORDE',costUnits=200,status='verified',
      provenance=sourceClassic,clientVerified=false,
      note='Frezza: south platform in Durotar. Source-backed; confirm the correct zeppelin in Forever.'},
    {id='horde_zeppelin_uc_og',from='horde_uc_og_tirisfal',to='horde_og_uc_durotar',
      mode='ZEPPELIN',faction='HORDE',costUnits=200,status='verified',
      provenance=sourceClassic,clientVerified=false,
      note='Zapetta: west platform in Tirisfal Glades. Source-backed; confirm the correct zeppelin in Forever.'},
  }
}
