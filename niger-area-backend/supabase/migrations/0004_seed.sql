-- Niger Area: launch data. Same numbers as the prototype, so balance tuning carries over.

insert into states (id, name, has_governor) values
  ('lagos', 'Lagos', true), ('kano', 'Kano', true), ('rivers', 'Rivers', true), ('enugu', 'Enugu', true),
  ('oyo', 'Oyo', true), ('kaduna', 'Kaduna', true), ('fct', 'Abuja FCT', false);

insert into lgas (id, state_id, name) values
  ('lagos-ikeja', 'lagos', 'Ikeja'), ('lagos-surulere', 'lagos', 'Surulere'), ('lagos-alimosho', 'lagos', 'Alimosho'),
  ('kano-nassarawa', 'kano', 'Nassarawa'), ('kano-fagge', 'kano', 'Fagge'), ('kano-dala', 'kano', 'Dala'),
  ('rivers-obio-akpor', 'rivers', 'Obio-Akpor'), ('rivers-port-harcourt', 'rivers', 'Port Harcourt'), ('rivers-bonny', 'rivers', 'Bonny'),
  ('enugu-nsukka', 'enugu', 'Nsukka'), ('enugu-enugu-north', 'enugu', 'Enugu North'), ('enugu-udi', 'enugu', 'Udi'),
  ('oyo-ibadan-north', 'oyo', 'Ibadan North'), ('oyo-ogbomosho', 'oyo', 'Ogbomosho'), ('oyo-iseyin', 'oyo', 'Iseyin'),
  ('kaduna-zaria', 'kaduna', 'Zaria'), ('kaduna-kaduna-south', 'kaduna', 'Kaduna South'), ('kaduna-kafanchan', 'kaduna', 'Kafanchan'),
  ('fct-amac', 'fct', 'AMAC'), ('fct-bwari', 'fct', 'Bwari'), ('fct-gwagwalada', 'fct', 'Gwagwalada');

insert into office_rules values
  ('LG',   'LG Chairman', 30,  2000,  300,  40000,  6000,  0,   8000, 1,    60000,   180000),
  ('SEN',  'Senator',     60,  5000,  500,  60000,  9000,  8,  20000, 2,   800000,  2000000),
  ('GOV',  'Governor',    60,  8000,  800, 150000, 20000, 15,  40000, 3,  1000000,  3000000),
  ('PRES', 'President',  120, 20000, 1500, 600000, 90000, 30, 120000, 6, 18000000, 25000000);

insert into campaign_actions (id, label, base_cost, energy, pop_min, pop_max, scandal, integrity, need_rep, rep_gain) values
  ('rally',       'Hold a rally',                  300, 1,  2,  5,  0,  0,  0, 0),
  ('posters',     'Posters and radio jingles',     600, 1,  3,  6,  0,  0,  0, 0),
  ('influencers', 'Pay influencers',              1200, 1,  4,  9,  0,  0,  0, 0),
  ('debate',      'Televised debate',                0, 2, -3,  8,  0,  2,  0, 1),
  ('ruler',       'Visit the traditional ruler',  2000, 1,  5,  9,  0,  0, 10, 0),
  ('rice',        'Share bags of rice',           2500, 1,  7, 12, 10,  0,  0, 0),
  ('buy',         'Buy votes at polling units',   5000, 1, 12, 18, 22, -8,  0, 0);

-- Houses and cars are tiers: each requires the one before. Owning tier N gives N x 4 (house) or N x 3 (car) status.
insert into shop_items (id, label, kind, tier, cost, status_points, daily_income, max_qty, requires) values
  ('house1', 'Self-contain',          'house', 1,  3000, 4, 0, 1, null),
  ('house2', '2-bedroom flat',        'house', 2,  8000, 4, 0, 1, 'house1'),
  ('house3', 'Bungalow',              'house', 3, 15000, 4, 0, 1, 'house2'),
  ('house4', 'Duplex in Lekki',       'house', 4, 35000, 4, 0, 1, 'house3'),
  ('house5', 'Mansion in Maitama',    'house', 5, 80000, 4, 0, 1, 'house4'),
  ('car1',   'Okada',                 'car',   1,  1500, 3, 0, 1, null),
  ('car2',   'Keke NAPEP',            'car',   2,  3500, 3, 0, 1, 'car1'),
  ('car3',   'Tokunbo Corolla',       'car',   3,  9000, 3, 0, 1, 'car2'),
  ('car4',   'Prado jeep',            'car',   4, 25000, 3, 0, 1, 'car3'),
  ('car5',   'G-Wagon convoy',        'car',   5, 60000, 3, 0, 1, 'car4'),
  ('gen',    'Generator',             'extra', 0,  1500, 2, 0, 1, null),
  ('borehole','Borehole',             'extra', 0,  2500, 2, 0, 1, null),
  ('spouse', 'Marriage',              'family',0,  6000, 3, 0, 1, null),
  ('child',  'Naming ceremony',       'family',0,  2000, 1, 0, 6, 'spouse'),
  ('pos',    'POS stand',             'business',0, 2000, 1,  60, 5, null),
  ('shop',   'Provision shop',        'business',0, 6000, 2, 180, 5, null),
  ('station','Filling station',       'business',0,25000, 5, 700, 5, null);

insert into coin_packs (id, kobo, coins) values
  ('small', 50000, 5000), ('medium', 100000, 12000), ('large', 200000, 30000);

-- Founding parties start with no members: in multiplayer, strength comes only from real players.
insert into parties (name, abbr, color) values
  ('Progressive Broom Congress', 'PBC', '#1F8A55'),
  ('People''s Umbrella Party',   'PUP', '#D2412F'),
  ('Labour Vanguard',            'LV',  '#3478C4'),
  ('New Progressives Movement',  'NPM', '#B07A18');

-- One jurisdiction and office per seat. Abuja FCT has no governor.
insert into jurisdictions (key, type, treasury) values ('PRES', 'PRES', 300000);
insert into jurisdictions (key, type, state_id, treasury)
  select 'SEN:' || id, 'SEN', id, 30000 from states;
insert into jurisdictions (key, type, state_id, treasury)
  select 'GOV:' || id, 'GOV', id, 75000 from states where has_governor;
insert into jurisdictions (key, type, state_id, lga_id, treasury)
  select 'LG:' || state_id || ':' || id, 'LG', state_id, id, 20000 from lgas;

-- Randomise starting conditions so no two states feel the same.
update jurisdictions set roads = 22 + floor(random() * 37), power = 22 + floor(random() * 37),
  health = 22 + floor(random() * 37), edu = 22 + floor(random() * 37),
  security = 22 + floor(random() * 37), economy = 22 + floor(random() * 37);

-- Staggered first polls so something is always coming up: LGs in week 1-2, then Senate, Governors, President.
insert into offices (key, term_ends_day)
  select key, case type when 'LG' then 7 + floor(random() * 8)::int
                        when 'SEN' then 21 + floor(random() * 10)::int
                        when 'GOV' then 35 + floor(random() * 15)::int
                        else 60 end
    from jurisdictions;
insert into elections (key, poll_day) select key, term_ends_day from offices;
