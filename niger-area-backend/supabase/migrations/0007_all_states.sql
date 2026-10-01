-- Niger Area: all 36 states plus the FCT, three real local governments each.
-- Additive: the 7 launch states keep their ids so existing citizens are unaffected.

update lgas set name = 'Jema''a (Kafanchan)' where id = 'kaduna-kafanchan';

insert into states (id, name, has_governor) values
  ('abia','Abia',true), ('adamawa','Adamawa',true), ('akwa-ibom','Akwa Ibom',true), ('anambra','Anambra',true),
  ('bauchi','Bauchi',true), ('bayelsa','Bayelsa',true), ('benue','Benue',true), ('borno','Borno',true),
  ('cross-river','Cross River',true), ('delta','Delta',true), ('ebonyi','Ebonyi',true), ('edo','Edo',true),
  ('ekiti','Ekiti',true), ('gombe','Gombe',true), ('imo','Imo',true), ('jigawa','Jigawa',true),
  ('katsina','Katsina',true), ('kebbi','Kebbi',true), ('kogi','Kogi',true), ('kwara','Kwara',true),
  ('nasarawa','Nasarawa',true), ('niger','Niger',true), ('ogun','Ogun',true), ('ondo','Ondo',true),
  ('osun','Osun',true), ('plateau','Plateau',true), ('sokoto','Sokoto',true), ('taraba','Taraba',true),
  ('yobe','Yobe',true), ('zamfara','Zamfara',true)
on conflict (id) do nothing;

insert into lgas (id, state_id, name) values
  ('abia-aba-north','abia','Aba North'), ('abia-umuahia-north','abia','Umuahia North'), ('abia-ohafia','abia','Ohafia'),
  ('adamawa-yola-north','adamawa','Yola North'), ('adamawa-mubi-north','adamawa','Mubi North'), ('adamawa-numan','adamawa','Numan'),
  ('akwa-ibom-uyo','akwa-ibom','Uyo'), ('akwa-ibom-eket','akwa-ibom','Eket'), ('akwa-ibom-ikot-ekpene','akwa-ibom','Ikot Ekpene'),
  ('anambra-awka-south','anambra','Awka South'), ('anambra-onitsha-north','anambra','Onitsha North'), ('anambra-nnewi-north','anambra','Nnewi North'),
  ('bauchi-bauchi','bauchi','Bauchi'), ('bauchi-katagum','bauchi','Katagum'), ('bauchi-misau','bauchi','Misau'),
  ('bayelsa-yenagoa','bayelsa','Yenagoa'), ('bayelsa-brass','bayelsa','Brass'), ('bayelsa-sagbama','bayelsa','Sagbama'),
  ('benue-makurdi','benue','Makurdi'), ('benue-gboko','benue','Gboko'), ('benue-otukpo','benue','Otukpo'),
  ('borno-maiduguri','borno','Maiduguri'), ('borno-biu','borno','Biu'), ('borno-bama','borno','Bama'),
  ('cross-river-calabar-municipal','cross-river','Calabar Municipal'), ('cross-river-ikom','cross-river','Ikom'), ('cross-river-ogoja','cross-river','Ogoja'),
  ('delta-warri-south','delta','Warri South'), ('delta-oshimili-south','delta','Oshimili South'), ('delta-ughelli-north','delta','Ughelli North'),
  ('ebonyi-abakaliki','ebonyi','Abakaliki'), ('ebonyi-afikpo-north','ebonyi','Afikpo North'), ('ebonyi-ezza-north','ebonyi','Ezza North'),
  ('edo-oredo','edo','Oredo'), ('edo-egor','edo','Egor'), ('edo-etsako-west','edo','Etsako West'),
  ('ekiti-ado-ekiti','ekiti','Ado Ekiti'), ('ekiti-ikere','ekiti','Ikere'), ('ekiti-ijero','ekiti','Ijero'),
  ('gombe-gombe','gombe','Gombe'), ('gombe-billiri','gombe','Billiri'), ('gombe-kaltungo','gombe','Kaltungo'),
  ('imo-owerri-municipal','imo','Owerri Municipal'), ('imo-orlu','imo','Orlu'), ('imo-okigwe','imo','Okigwe'),
  ('jigawa-dutse','jigawa','Dutse'), ('jigawa-hadejia','jigawa','Hadejia'), ('jigawa-kazaure','jigawa','Kazaure'),
  ('katsina-katsina','katsina','Katsina'), ('katsina-daura','katsina','Daura'), ('katsina-funtua','katsina','Funtua'),
  ('kebbi-birnin-kebbi','kebbi','Birnin Kebbi'), ('kebbi-argungu','kebbi','Argungu'), ('kebbi-yauri','kebbi','Yauri'),
  ('kogi-lokoja','kogi','Lokoja'), ('kogi-okene','kogi','Okene'), ('kogi-idah','kogi','Idah'),
  ('kwara-ilorin-west','kwara','Ilorin West'), ('kwara-offa','kwara','Offa'), ('kwara-patigi','kwara','Patigi'),
  ('nasarawa-lafia','nasarawa','Lafia'), ('nasarawa-keffi','nasarawa','Keffi'), ('nasarawa-akwanga','nasarawa','Akwanga'),
  ('niger-chanchaga','niger','Chanchaga'), ('niger-bida','niger','Bida'), ('niger-suleja','niger','Suleja'),
  ('ogun-abeokuta-south','ogun','Abeokuta South'), ('ogun-ijebu-ode','ogun','Ijebu Ode'), ('ogun-sagamu','ogun','Sagamu'),
  ('ondo-akure-south','ondo','Akure South'), ('ondo-ondo-west','ondo','Ondo West'), ('ondo-owo','ondo','Owo'),
  ('osun-osogbo','osun','Osogbo'), ('osun-ife-central','osun','Ife Central'), ('osun-ilesa-east','osun','Ilesa East'),
  ('plateau-jos-north','plateau','Jos North'), ('plateau-pankshin','plateau','Pankshin'), ('plateau-shendam','plateau','Shendam'),
  ('sokoto-sokoto-north','sokoto','Sokoto North'), ('sokoto-wamako','sokoto','Wamako'), ('sokoto-tambuwal','sokoto','Tambuwal'),
  ('taraba-jalingo','taraba','Jalingo'), ('taraba-wukari','taraba','Wukari'), ('taraba-takum','taraba','Takum'),
  ('yobe-damaturu','yobe','Damaturu'), ('yobe-potiskum','yobe','Potiskum'), ('yobe-nguru','yobe','Nguru'),
  ('zamfara-gusau','zamfara','Gusau'), ('zamfara-kaura-namoda','zamfara','Kaura Namoda'), ('zamfara-talata-mafara','zamfara','Talata Mafara')
on conflict (id) do nothing;

-- Seats for the new states, with randomised starting conditions.
insert into jurisdictions (key, type, state_id, treasury)
  select 'SEN:' || id, 'SEN', id, 30000 from states where 'SEN:' || id not in (select key from jurisdictions);
insert into jurisdictions (key, type, state_id, treasury)
  select 'GOV:' || id, 'GOV', id, 75000 from states where has_governor and 'GOV:' || id not in (select key from jurisdictions);
insert into jurisdictions (key, type, state_id, lga_id, treasury)
  select 'LG:' || state_id || ':' || id, 'LG', state_id, id, 20000 from lgas
   where 'LG:' || state_id || ':' || id not in (select key from jurisdictions);

update jurisdictions set roads = 22 + floor(random() * 37), power = 22 + floor(random() * 37),
  health = 22 + floor(random() * 37), edu = 22 + floor(random() * 37),
  security = 22 + floor(random() * 37), economy = 22 + floor(random() * 37)
 where key not in (select key from offices);

-- First polls staggered from today so the new seats open up over the coming weeks.
insert into offices (key, term_ends_day)
  select j.key, (select day from game_clock where id = 1) + case j.type when 'LG' then 5 + floor(random() * 10)::int
                                                                      when 'SEN' then 18 + floor(random() * 12)::int
                                                                      else 30 + floor(random() * 20)::int end
    from jurisdictions j where j.key not in (select key from offices);
insert into elections (key, poll_day)
  select o.key, o.term_ends_day from offices o
   where not exists (select 1 from elections e where e.key = o.key and e.status = 'open');
