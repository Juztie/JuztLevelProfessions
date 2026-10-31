-- Build-70450 owner Excel / UI-map evidence inventory. No navigation or native rights.
local _,JLP=...
local M={contract="jlp-transport-audit-70450-v1",sourceSHA='7db7b31ef0fe6352bfaf1729b88315bd0552722feada527496a87617ace890cf',nativeDispatchAllowed=false}
local places={}
places[#places+1]={id='ST025',name='Booty Bay',zone='Stranglethorn Vale',category='Flight Path',x=0.268,y=0.77,mapID=1434,mapEvidence='UI_MAP_70450_SYSTEM0_UNIQUE_NAME'}
places[#places+1]={id='ST021',name='Flame Crest',zone='Burning Steppes',category='Flight Path',x=0.6559999999999999,y=0.242,mapID=1428,mapEvidence='UI_MAP_70450_SYSTEM0_UNIQUE_NAME'}
places[#places+1]={id='ST026',name='Grom\'gol Base Camp',zone='Stranglethorn Vale',category='Flight Path',x=0.324,y=0.292,mapID=1434,mapEvidence='UI_MAP_70450_SYSTEM0_UNIQUE_NAME'}
places[#places+1]={id='ST020',name='Hammerfall',zone='Arathi Highlands',category='Flight Path',x=0.73,y=0.326,mapID=1417,mapEvidence='UI_MAP_70450_SYSTEM0_UNIQUE_NAME'}
places[#places+1]={id='ST030',name='Kargath',zone='Badlands',category='Flight Path',x=0.04,y=0.44799999999999995,mapID=1418,mapEvidence='UI_MAP_70450_SYSTEM0_UNIQUE_NAME'}
places[#places+1]={id='ST029',name='Light\'s Hope Chapel',zone='Eastern Plaguelands',category='Flight Path',x=0.705,y=0.475,mapID=1423,mapEvidence='UI_MAP_70450_SYSTEM0_UNIQUE_NAME'}
places[#places+1]={id='ST019',name='Revantusk Village',zone='The Hinterlands',category='Flight Path',x=0.816,y=0.818,mapID=1425,mapEvidence='UI_MAP_70450_SYSTEM0_UNIQUE_NAME'}
places[#places+1]={id='ST022',name='Rog\'mar',zone='Riverglades',category='Flight Path',x=0.596,y=0.45,mapID=2548,mapEvidence='UI_MAP_70450_SYSTEM0_UNIQUE_NAME'}
places[#places+1]={id='ST024',name='Stonard',zone='Swamp of Sorrows',category='Flight Path',x=0.46,y=0.546,mapID=1435,mapEvidence='UI_MAP_70450_SYSTEM0_UNIQUE_NAME'}
places[#places+1]={id='ST018',name='Tarren Mill',zone='Hillsbrad Foothills',category='Flight Path',x=0.602,y=0.18600000000000003,mapID=1424,mapEvidence='UI_MAP_70450_SYSTEM0_UNIQUE_NAME'}
places[#places+1]={id='ST017',name='The Sepulcher',zone='Silverpine Forest',category='Flight Path',x=0.456,y=0.424,mapID=1421,mapEvidence='UI_MAP_70450_SYSTEM0_UNIQUE_NAME'}
places[#places+1]={id='ST031',name='Thorium Point',zone='Searing Gorge',category='Flight Path',x=0.348,y=0.308,mapID=1427,mapEvidence='UI_MAP_70450_SYSTEM0_UNIQUE_NAME'}
places[#places+1]={id='ST016',name='Undercity',zone='Tirisfal Glades',category='Flight Path',x=0.613,y=0.754,mapID=1420,mapEvidence='UI_MAP_70450_SYSTEM0_UNIQUE_NAME'}
places[#places+1]={id='ST001',name='Bloodvenom Post',zone='Felwood',category='Flight Path',x=0.344,y=0.5379999999999999,mapID=1448,mapEvidence='UI_MAP_70450_SYSTEM0_UNIQUE_NAME'}
places[#places+1]={id='ST012',name='Brackenwall Village',zone='Dustwallow Marsh',category='Flight Path',x=0.35600000000000004,y=0.318,mapID=1445,mapEvidence='UI_MAP_70450_SYSTEM0_UNIQUE_NAME'}
places[#places+1]={id='ST013',name='Camp Mojache',zone='Feralas',category='Flight Path',x=0.754,y=0.442,mapID=1444,mapEvidence='UI_MAP_70450_SYSTEM0_UNIQUE_NAME'}
places[#places+1]={id='ST046',name='Camp Taurajo',zone='The Barrens',category='Flight Path',x=0.444,y=0.59,mapID=1413,mapEvidence='UI_MAP_70450_SYSTEM0_UNIQUE_NAME'}
places[#places+1]={id='ST032',name='Cenarion Hold',zone='Silithus',category='Flight Path',x=0.488,y=0.366,mapID=1451,mapEvidence='UI_MAP_70450_SYSTEM0_UNIQUE_NAME'}
places[#places+1]={id='ST027',name='Everlook',zone='Winterspring',category='Flight Path',x=0.604,y=0.364,mapID=1452,mapEvidence='UI_MAP_70450_SYSTEM0_UNIQUE_NAME'}
places[#places+1]={id='ST047',name='Freewind Post',zone='Thousand Needles',category='Flight Path',x=0.45,y=0.49200000000000005,mapID=1441,mapEvidence='UI_MAP_70450_SYSTEM0_UNIQUE_NAME'}
places[#places+1]={id='ST015',name='Gadgetzan',zone='Tanaris',category='Flight Path',x=0.516,y=0.254,mapID=1446,mapEvidence='UI_MAP_70450_SYSTEM0_UNIQUE_NAME'}
places[#places+1]={id='ST014',name='Marshal\'s Refuge',zone='Un\'Goro Crater',category='Flight Path',x=0.452,y=0.057999999999999996,mapID=1449,mapEvidence='UI_MAP_70450_SYSTEM0_UNIQUE_NAME'}
places[#places+1]={id='ST028',name='Moonglade',zone='Moonglade',category='Flight Path',x=0.322,y=0.664,mapID=1450,mapEvidence='UI_MAP_70450_SYSTEM0_UNIQUE_NAME'}
places[#places+1]={id='ST048',name='Nighthaven',zone='Moonglade',category='Flight Path',x=0.322,y=0.664,mapID=1450,mapEvidence='UI_MAP_70450_SYSTEM0_UNIQUE_NAME',requiresClass='DRUID'}
places[#places+1]={id='ST007',name='Orgrimmar',zone='Orgrimmar',category='Flight Path',x=0.452,y=0.638,mapID=1454,mapEvidence='UI_MAP_70450_SYSTEM0_UNIQUE_NAME'}
places[#places+1]={id='ST011',name='Ratchet',zone='The Barrens',category='Flight Path',x=0.63,y=0.37200000000000005,mapID=1413,mapEvidence='UI_MAP_70450_SYSTEM0_UNIQUE_NAME'}
places[#places+1]={id='ST040',name='Shadowprey Village',zone='Desolace',category='Flight Path',x=0.21600000000000003,y=0.74,mapID=1443,mapEvidence='UI_MAP_70450_SYSTEM0_UNIQUE_NAME'}
places[#places+1]={id='ST006',name='Splintertree Post',zone='Ashenvale',category='Flight Path',x=0.732,y=0.616,mapID=1440,mapEvidence='UI_MAP_70450_SYSTEM0_UNIQUE_NAME'}
places[#places+1]={id='ST002',name='Summit of Eternity',zone='Mount Hyjal',category='Flight Path',x=0.6859999999999999,y=0.44,mapID=2482,mapEvidence='UI_MAP_70450_SYSTEM0_UNIQUE_NAME'}
places[#places+1]={id='ST008',name='Sun Rock Retreat',zone='Stonetalon Mountains',category='Flight Path',x=0.452,y=0.598,mapID=1442,mapEvidence='UI_MAP_70450_SYSTEM0_UNIQUE_NAME'}
places[#places+1]={id='ST003',name='Tainted Foothills',zone='Mount Hyjal',category='Flight Path',x=0.55,y=0.828,mapID=2482,mapEvidence='UI_MAP_70450_SYSTEM0_UNIQUE_NAME'}
places[#places+1]={id='ST009',name='The Crossroads',zone='The Barrens',category='Flight Path',x=0.514,y=0.302,mapID=1413,mapEvidence='UI_MAP_70450_SYSTEM0_UNIQUE_NAME'}
places[#places+1]={id='ST010',name='Thunder Bluff',zone='Thunder Bluff',category='Flight Path',x=0.46799999999999997,y=0.5,mapID=1456,mapEvidence='UI_MAP_70450_SYSTEM0_UNIQUE_NAME'}
places[#places+1]={id='ST005',name='Valormok',zone='Azshara',category='Flight Path',x=0.22,y=0.496,mapID=1447,mapEvidence='UI_MAP_70450_SYSTEM0_UNIQUE_NAME'}
places[#places+1]={id='ST004',name='Zoram\'gar Outpost',zone='Ashenvale',category='Flight Path',x=0.122,y=0.33799999999999997,mapID=1440,mapEvidence='UI_MAP_70450_SYSTEM0_UNIQUE_NAME'}
places[#places+1]={id='ST043',name='Tirisfal Glades',zone='Tirisfal Glades',category='Zeppelin',x=0.606,y=0.589,mapID=1420,mapEvidence='UI_MAP_70450_SYSTEM0_UNIQUE_NAME'}
places[#places+1]={id='ST037',name='Durotar',zone='Durotar',category='Zeppelin',x=0.51,y=0.139,mapID=1411,mapEvidence='UI_MAP_70450_SYSTEM0_UNIQUE_NAME'}
places[#places+1]={id='ST038',name='Durotar',zone='Durotar',category='Zeppelin',x=0.505,y=0.127,mapID=1411,mapEvidence='UI_MAP_70450_SYSTEM0_UNIQUE_NAME'}
places[#places+1]={id='ST039',name='Thunder Bluff',zone='Mulgore',category='Zeppelin',x=0.34299999999999997,y=0.261,mapID=1412,mapEvidence='UI_MAP_70450_SYSTEM0_UNIQUE_NAME'}
places[#places+1]={id='ST044',name='Grom\'gol Base Camp',zone='Stranglethorn Vale',category='Zeppelin',x=0.312,y=0.304,mapID=1434,mapEvidence='UI_MAP_70450_SYSTEM0_UNIQUE_NAME'}
places[#places+1]={id='ST045',name='Grom\'gol Base Camp',zone='Stranglethorn Vale',category='Zeppelin',x=0.315,y=0.29100000000000004,mapID=1434,mapEvidence='UI_MAP_70450_SYSTEM0_UNIQUE_NAME'}
places[#places+1]={id='ST042',name='Tirisfal Glades',zone='Tirisfal Glades',category='Zeppelin',x=0.619,y=0.589,mapID=1420,mapEvidence='UI_MAP_70450_SYSTEM0_UNIQUE_NAME'}
places[#places+1]={id='ST041',name='Valanaar',zone='Zephras Isle',category='Zeppelin',x=0.5770000000000001,y=0.81,mapID=2521,mapEvidence='UI_MAP_70450_SYSTEM0_UNIQUE_NAME',alternateMapIDs={2665}}
places[#places+1]={id='ST035',name='Riverglades',zone='Riverglades',category='Boat',x=0.8059999999999999,y=0.546,mapID=2548,mapEvidence='UI_MAP_70450_SYSTEM0_UNIQUE_NAME'}
places[#places+1]={id='ST036',name='Booty Bay',zone='Stranglethorn Vale',category='Boat',x=0.257,y=0.731,mapID=1434,mapEvidence='UI_MAP_70450_SYSTEM0_UNIQUE_NAME'}
places[#places+1]={id='ST034',name='Tanaris',zone='Tanaris',category='Boat',x=0.6859999999999999,y=0.23,mapID=1446,mapEvidence='UI_MAP_70450_SYSTEM0_UNIQUE_NAME'}
places[#places+1]={id='ST033',name='Ratchet',zone='The Barrens',category='Boat',x=0.638,y=0.38799999999999996,mapID=1413,mapEvidence='UI_MAP_70450_SYSTEM0_UNIQUE_NAME'}
local routes={}
routes[#routes+1]={id='R001',fromST='ST043',toST='ST037',mode='ZEPPELIN',faction='HORDE',returnRoute='R002'}
routes[#routes+1]={id='R002',fromST='ST037',toST='ST043',mode='ZEPPELIN',faction='HORDE',returnRoute='R001'}
routes[#routes+1]={id='R003',fromST='ST038',toST='ST044',mode='ZEPPELIN',faction='HORDE',returnRoute='R005'}
routes[#routes+1]={id='R004',fromST='ST039',toST='ST041',mode='ZEPPELIN',faction='HORDE',returnRoute='R008'}
routes[#routes+1]={id='R005',fromST='ST044',toST='ST038',mode='ZEPPELIN',faction='HORDE',returnRoute='R003'}
routes[#routes+1]={id='R006',fromST='ST045',toST='ST042',mode='ZEPPELIN',faction='HORDE',returnRoute='R007'}
routes[#routes+1]={id='R007',fromST='ST042',toST='ST045',mode='ZEPPELIN',faction='HORDE',returnRoute='R006'}
routes[#routes+1]={id='R008',fromST='ST041',toST='ST039',mode='ZEPPELIN',faction='HORDE',returnRoute='R004'}
routes[#routes+1]={id='R009',fromST='ST035',toST='ST034',mode='BOAT',faction='NEUTRAL',returnRoute='R011'}
routes[#routes+1]={id='R010',fromST='ST036',toST='ST033',mode='BOAT',faction='NEUTRAL',returnRoute='R012'}
routes[#routes+1]={id='R011',fromST='ST034',toST='ST035',mode='BOAT',faction='NEUTRAL',returnRoute='R009'}
routes[#routes+1]={id='R012',fromST='ST033',toST='ST036',mode='BOAT',faction='NEUTRAL',returnRoute='R010'}
routes[#routes+1]={id='R013',fromST='ST025',toST='ST026',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R014',fromST='ST025',toST='ST030',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R015',fromST='ST025',toST='ST024',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R016',fromST='ST021',toST='ST030',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R017',fromST='ST021',toST='ST022',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R018',fromST='ST021',toST='ST024',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R019',fromST='ST021',toST='ST031',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R020',fromST='ST026',toST='ST025',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R021',fromST='ST026',toST='ST030',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R022',fromST='ST026',toST='ST024',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R023',fromST='ST020',toST='ST030',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R024',fromST='ST020',toST='ST019',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R025',fromST='ST020',toST='ST022',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R026',fromST='ST020',toST='ST018',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R027',fromST='ST020',toST='ST016',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R028',fromST='ST030',toST='ST025',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R029',fromST='ST030',toST='ST021',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R030',fromST='ST030',toST='ST026',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R031',fromST='ST030',toST='ST020',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R032',fromST='ST030',toST='ST022',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R033',fromST='ST030',toST='ST024',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R034',fromST='ST030',toST='ST031',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R035',fromST='ST030',toST='ST016',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R036',fromST='ST029',toST='ST019',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R037',fromST='ST029',toST='ST016',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R038',fromST='ST019',toST='ST020',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R039',fromST='ST019',toST='ST029',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R040',fromST='ST019',toST='ST018',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R041',fromST='ST019',toST='ST016',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R042',fromST='ST022',toST='ST021',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R043',fromST='ST022',toST='ST020',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R044',fromST='ST022',toST='ST030',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R045',fromST='ST022',toST='ST024',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R046',fromST='ST024',toST='ST025',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R047',fromST='ST024',toST='ST021',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R048',fromST='ST024',toST='ST026',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R049',fromST='ST024',toST='ST030',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R050',fromST='ST024',toST='ST022',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R051',fromST='ST018',toST='ST020',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R052',fromST='ST018',toST='ST019',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R053',fromST='ST018',toST='ST017',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R054',fromST='ST018',toST='ST016',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R055',fromST='ST017',toST='ST018',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R056',fromST='ST017',toST='ST016',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R057',fromST='ST031',toST='ST021',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R058',fromST='ST031',toST='ST030',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R059',fromST='ST016',toST='ST020',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R060',fromST='ST016',toST='ST030',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R061',fromST='ST016',toST='ST029',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R062',fromST='ST016',toST='ST019',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R063',fromST='ST016',toST='ST018',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R064',fromST='ST016',toST='ST017',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R065',fromST='ST001',toST='ST027',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R066',fromST='ST001',toST='ST028',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R067',fromST='ST001',toST='ST007',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R068',fromST='ST001',toST='ST009',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R069',fromST='ST001',toST='ST005',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R070',fromST='ST012',toST='ST015',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R071',fromST='ST012',toST='ST007',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R072',fromST='ST012',toST='ST009',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R073',fromST='ST012',toST='ST010',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R074',fromST='ST013',toST='ST032',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R075',fromST='ST013',toST='ST047',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R076',fromST='ST013',toST='ST015',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R077',fromST='ST013',toST='ST040',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R078',fromST='ST013',toST='ST009',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R079',fromST='ST013',toST='ST010',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R080',fromST='ST046',toST='ST047',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R081',fromST='ST046',toST='ST009',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R082',fromST='ST046',toST='ST010',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R083',fromST='ST032',toST='ST013',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R084',fromST='ST032',toST='ST015',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R085',fromST='ST032',toST='ST014',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R086',fromST='ST027',toST='ST001',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R087',fromST='ST027',toST='ST028',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R088',fromST='ST027',toST='ST007',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R089',fromST='ST027',toST='ST003',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R090',fromST='ST027',toST='ST005',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R091',fromST='ST047',toST='ST013',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R092',fromST='ST047',toST='ST046',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R093',fromST='ST047',toST='ST015',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R094',fromST='ST047',toST='ST009',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R095',fromST='ST047',toST='ST010',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R096',fromST='ST015',toST='ST012',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R097',fromST='ST015',toST='ST013',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R098',fromST='ST015',toST='ST032',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R099',fromST='ST015',toST='ST047',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R100',fromST='ST015',toST='ST014',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R101',fromST='ST015',toST='ST007',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R102',fromST='ST015',toST='ST009',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R103',fromST='ST015',toST='ST010',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R104',fromST='ST014',toST='ST032',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R105',fromST='ST014',toST='ST015',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R106',fromST='ST028',toST='ST001',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R107',fromST='ST028',toST='ST027',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R108',fromST='ST048',toST='ST010',mode='FLIGHT',faction='HORDE',requiresClass='DRUID'}
routes[#routes+1]={id='R109',fromST='ST007',toST='ST001',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R110',fromST='ST007',toST='ST012',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R111',fromST='ST007',toST='ST027',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R112',fromST='ST007',toST='ST015',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R113',fromST='ST007',toST='ST006',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R114',fromST='ST007',toST='ST009',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R115',fromST='ST007',toST='ST010',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R116',fromST='ST007',toST='ST005',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R117',fromST='ST011',toST='ST009',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R118',fromST='ST040',toST='ST013',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R119',fromST='ST040',toST='ST008',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R120',fromST='ST040',toST='ST010',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R121',fromST='ST006',toST='ST007',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R122',fromST='ST006',toST='ST009',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R123',fromST='ST006',toST='ST005',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R124',fromST='ST006',toST='ST004',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R125',fromST='ST002',toST='ST003',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R126',fromST='ST008',toST='ST040',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R127',fromST='ST008',toST='ST009',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R128',fromST='ST008',toST='ST010',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R129',fromST='ST003',toST='ST027',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R130',fromST='ST003',toST='ST002',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R131',fromST='ST009',toST='ST001',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R132',fromST='ST009',toST='ST012',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R133',fromST='ST009',toST='ST013',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R134',fromST='ST009',toST='ST046',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R135',fromST='ST009',toST='ST047',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R136',fromST='ST009',toST='ST015',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R137',fromST='ST009',toST='ST007',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R138',fromST='ST009',toST='ST011',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R139',fromST='ST009',toST='ST006',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R140',fromST='ST009',toST='ST008',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R141',fromST='ST009',toST='ST010',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R142',fromST='ST009',toST='ST005',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R143',fromST='ST009',toST='ST004',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R144',fromST='ST010',toST='ST012',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R145',fromST='ST010',toST='ST013',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R146',fromST='ST010',toST='ST046',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R147',fromST='ST010',toST='ST047',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R148',fromST='ST010',toST='ST015',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R149',fromST='ST010',toST='ST048',mode='FLIGHT',faction='HORDE',requiresClass='DRUID'}
routes[#routes+1]={id='R150',fromST='ST010',toST='ST007',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R151',fromST='ST010',toST='ST040',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R152',fromST='ST010',toST='ST008',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R153',fromST='ST010',toST='ST009',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R154',fromST='ST010',toST='ST005',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R155',fromST='ST005',toST='ST001',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R156',fromST='ST005',toST='ST027',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R157',fromST='ST005',toST='ST007',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R158',fromST='ST005',toST='ST006',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R159',fromST='ST005',toST='ST009',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R160',fromST='ST005',toST='ST010',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R161',fromST='ST004',toST='ST006',mode='FLIGHT',faction='HORDE'}
routes[#routes+1]={id='R162',fromST='ST004',toST='ST009',mode='FLIGHT',faction='HORDE'}
local function byId(rows)
 local out={}
 for _,row in ipairs(rows or {}) do
   if type(row)~='table' or type(row.id)~='string' or out[row.id] then return nil end
   out[row.id]=row
 end
 return out
end
local function eq(a,b)
 if type(a)~=type(b) then return false end
 if type(a)~='table' then return a==b end
 for k,v in pairs(a) do if not eq(v,b[k]) then return false end end
 for k in pairs(b) do if a[k]==nil then return false end end
 return true
end
function M:Audit()
 local result={contract=self.contract,sourceSHA=self.sourceSHA,
   expectedPlaces=#places,expectedRoutes=#routes,expectedFlightMasters=35,
   expectedFlightRoutes=150,expectedZeppelins=8,expectedBoats=4,
   sourceReportedFlightMasters=36,sourceHeaderCountConflict=true,
   verifiedClientSpawns=0,nativeBoardingVerified=false,
   navigationAuthorityIncrement=0,productionAuthority=false,errors={}}
 local owner=JLP:GetModule('OwnerAuthorizedNavigation')
 if not owner or type(owner.GetTransportPlaces)~='function' or
    type(owner.GetTransportSourceRoutes)~='function' then
    result.status='OWNER_SOURCE_UNAVAILABLE';return result end
 local original=byId(owner:GetTransportPlaces())
 local links=byId(owner:GetTransportSourceRoutes())
 if not original or not links then
    result.status='DUPLICATE_OWNER_IDENTITIES';return result end
 local countP,countR=0,0
 for _ in pairs(original) do countP=countP+1 end
 for _ in pairs(links) do countR=countR+1 end
 if countP~=#places or countR~=#routes then result.errors[#result.errors+1]='SOURCE_ROW_COUNT_MISMATCH' end
 for _,p in ipairs(places) do
   local q=original[p.id]
   if not q or q.zone~=p.zone or q.x~=p.x or q.y~=p.y or
      q.mapID~=p.mapID or q.category~=p.category or
      (p.category=='Flight Path' and q.flightPoint~=p.name) then
      result.errors[#result.errors+1]='PLACE_'..p.id
   end
 end
 for _,r in ipairs(routes) do
   local q=links[r.id]
   if not q or q.fromST~=r.fromST or q.toST~=r.toST or
      q.mode~=r.mode or q.faction~=r.faction or
      q.requiresUnlock~=(r.mode=='FLIGHT') or
      q.sourceSHA~=self.sourceSHA or
      (r.requiresClass=='DRUID' and
        (original[r.fromST].access~='Kun Druid' and original[r.toST].access~='Kun Druid')) then
      result.errors[#result.errors+1]='ROUTE_'..r.id
   end
 end
 result.status=#result.errors==0 and 'SOURCE_PARITY_OK_NOT_LIVE_VERIFIED' or 'SOURCE_PARITY_FAILED'
 result.ownerConnectionsPreserved=(#result.errors==0) and #routes or 0
 return result
end
function M:GetPlace(stID)
 if type(stID)~='string' then return nil,'INVALID_STOP_ID' end
 for _,p in ipairs(places) do
  if p.id==stID then
   local item={id=p.id,name=p.name,zone=p.zone,category=p.category,
      mapID=p.mapID,mapEvidence=p.mapEvidence,x=p.x,y=p.y,
      sourceSHA=self.sourceSHA,clientObserved=false,navigationAuthority=false,
      requiresClass=p.requiresClass,alternateMapIDs={}}
   for i,v in ipairs(p.alternateMapIDs or {}) do item.alternateMapIDs[i]=v end
   return item
  end
 end
 return nil,'STOP_UNKNOWN'
end
function M:GetRoute(routeID)
 if type(routeID)~='string' then return nil,'INVALID_ROUTE_ID' end
 for _,r in ipairs(routes) do
  if r.id==routeID then
   return {id=r.id,fromST=r.fromST,toST=r.toST,mode=r.mode,
     faction=r.faction,requiresClass=r.requiresClass,
     requiresUnlock=r.mode=='FLIGHT',returnRoute=r.returnRoute,
     sourceSHA=self.sourceSHA,sourceConfirmed=true,clientObserved=false,
     navigationAuthority=false,productionAuthority=false}
  end
 end
 return nil,'ROUTE_UNKNOWN'
end
JLP:RegisterModule('TransportNetworkAudit70450',M)
