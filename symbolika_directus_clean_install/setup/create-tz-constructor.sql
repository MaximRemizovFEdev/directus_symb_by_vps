-- Symbolika TZ constructor dictionaries and rules.
-- Stores dynamic form definitions for technical tasks by category/subcategory/method.

ALTER TABLE contractors ADD COLUMN IF NOT EXISTS can_mount boolean DEFAULT false;

CREATE TABLE IF NOT EXISTS tz_constructor_specs (
  id serial PRIMARY KEY,
  category integer REFERENCES product_categories(id) ON DELETE SET NULL,
  subcategory integer REFERENCES product_subcategories(id) ON DELETE SET NULL,
  application_method integer REFERENCES product_application_methods(id) ON DELETE SET NULL,
  category_name text NOT NULL,
  subcategory_name text,
  application_method_name text,
  route_area text DEFAULT 'production',
  contractor_1_role text,
  contractor_2_role text,
  fields jsonb NOT NULL DEFAULT '[]'::jsonb,
  template text NOT NULL DEFAULT '',
  example text,
  active boolean NOT NULL DEFAULT true,
  sort integer NOT NULL DEFAULT 100,
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS tz_constructor_specs_unique_names
  ON tz_constructor_specs (
    category_name,
    COALESCE(subcategory_name, ''),
    COALESCE(application_method_name, '')
  );

COMMENT ON TABLE tz_constructor_specs IS 'Definitions for dynamic technical task constructor forms.';
COMMENT ON COLUMN tz_constructor_specs.fields IS 'JSON array of constructor fields, options and conditional display rules.';
COMMENT ON COLUMN tz_constructor_specs.template IS 'Template used by UI to assemble technical task text.';

INSERT INTO product_categories (name, detail_mode, sort, is_active)
SELECT c.name, c.detail_mode, c.sort, c.is_active
FROM (VALUES
  ('Постеры', 'none', 15, true),
  ('Изделия из акрила и фанеры', 'subcategory', 95, true)
) AS c(name, detail_mode, sort, is_active)
WHERE NOT EXISTS (
  SELECT 1 FROM product_categories pc WHERE pc.name = c.name
);

INSERT INTO product_subcategories (category, name, sort, is_active)
SELECT pc.id, s.name, s.sort, true
FROM (VALUES
  ('Полиграфия', 'Открытки', 80),
  ('Полиграфия', 'Бейджи', 90),
  ('Полиграфия', 'Закладки', 100),
  ('Конструкции', 'Паук', 50),
  ('Изделия из акрила и фанеры', 'Брелки', 10),
  ('Изделия из акрила и фанеры', 'Значки', 20),
  ('Изделия из акрила и фанеры', 'Магниты', 30),
  ('Изделия из акрила и фанеры', 'Стелы', 40)
) AS s(category_name, name, sort)
JOIN product_categories pc ON pc.name = s.category_name
WHERE NOT EXISTS (
  SELECT 1
  FROM product_subcategories ps
  WHERE ps.category = pc.id
    AND ps.name = s.name
);

INSERT INTO product_application_methods (category, name, sort, is_active)
SELECT pc.id, m.name, m.sort, true
FROM (VALUES
  ('Сувениры, мерч', 'Цифровая печать', 5),
  ('Упаковка', 'УФ-печать', 10),
  ('Упаковка', 'Шелкография', 20),
  ('Изделия из акрила и фанеры', 'Гравировка', 10),
  ('Изделия из акрила и фанеры', 'УФ-печать', 20)
) AS m(category_name, name, sort)
JOIN product_categories pc ON pc.name = m.category_name
WHERE NOT EXISTS (
  SELECT 1
  FROM product_application_methods pam
  WHERE pam.category = pc.id
    AND pam.name = m.name
);

UPDATE product_categories
SET detail_mode = CASE
  WHEN name IN ('Сувениры, мерч', 'Текстиль', 'Нанесение') THEN 'application_method'
  WHEN name IN ('Баннеры', 'ПВХ - таблички', 'Постеры') THEN 'none'
  ELSE 'subcategory'
END
WHERE name IN (
  'Полиграфия', 'Баннеры', 'Наклейки', 'ПВХ - таблички', 'Постеры',
  'Сувениры, мерч', 'Упаковка', 'Текстиль', 'Ткани', 'Конструкции',
  'Нанесение', 'Изделия из акрила и фанеры'
);

INSERT INTO product_routing_rules (name, product_category, contractor_1, priority, is_active)
SELECT 'Полиграфия -> Производство', pc.id, c.id, 10, true
FROM product_categories pc
JOIN contractors c ON c.name = 'Собственное производство'
WHERE pc.name = 'Полиграфия'
  AND NOT EXISTS (
    SELECT 1 FROM product_routing_rules r
    WHERE r.name = 'Полиграфия -> Производство'
  );

DROP TABLE IF EXISTS _tz_constructor_seed;

CREATE TEMP TABLE _tz_constructor_seed (
  category_name text,
  subcategory_name text,
  application_method_name text,
  route_area text,
  contractor_1_role text,
  contractor_2_role text,
  fields jsonb,
  template text,
  example text,
  sort integer
);

INSERT INTO _tz_constructor_seed (
  category_name, subcategory_name, application_method_name,
  route_area, contractor_1_role, contractor_2_role,
  fields, template, example, sort
) VALUES
(
  'Полиграфия', 'Грамоты', NULL,
  'production', 'Собственное производство', NULL,
  $json$[
    {"key":"format","label":"Формат","type":"select","required":true,"options":["А5","А4","А3"]},
    {"key":"paper","label":"Бумага","type":"select","required":true,"options":["80 гр офисная","130 гр мелованная матовая","130 гр мелованная глянцевая","170 гр мелованная матовая","170 гр мелованная глянцевая","200 гр мелованная матовая","200 гр мелованная глянцевая","250 гр мелованная матовая","250 гр мелованная глянцевая","300 гр мелованная матовая","300 гр мелованная глянцевая","Дизайнерская","Крафт-бумага"]},
    {"key":"print_color","label":"Цветность печати","type":"select","required":true,"options":["4+0","1+0"]},
    {"key":"comment","label":"Комментарий к ТЗ","type":"textarea","required":false}
  ]$json$::jsonb,
  '{{quantity}} грамот формата {{format}}, бумага {{paper}}, {{print_color}}{{#comment}}. {{comment}}{{/comment}}',
  '20 грамот формата А4, бумага 300 гр мелованная матовая, 4+0',
  10
),
(
  'Полиграфия', 'Визитки', NULL,
  'production', 'Собственное производство', 'Шелкография при УФ-лаке',
  $json$[
    {"key":"paper","label":"Бумага","type":"select","required":true,"default":"300 гр мелованная матовая","options":["300 гр мелованная матовая","300 гр мелованная глянцевая"]},
    {"key":"print_color","label":"Цветность печати","type":"select","required":true,"options":["1+0","1+1","4+0","4+1","4+4"]},
    {"key":"lamination","label":"Ламинация","type":"checkbox","required":false},
    {"key":"lamination_type","label":"Тип ламинации","type":"select","required":true,"options":["Матовая","Глянцевая","Софт-тач"],"show_when":{"lamination":true}},
    {"key":"lamination_thickness","label":"Плотность ламинации","type":"select","required":true,"options":["32 мкн","125 мкн","250 мкн"],"show_when":{"lamination":true}},
    {"key":"rounded_corners","label":"Скруглить углы","type":"checkbox","required":false},
    {"key":"uv_lacquer","label":"УФ-лак","type":"checkbox","required":false},
    {"key":"comment","label":"Комментарий к ТЗ","type":"textarea","required":false}
  ]$json$::jsonb,
  '{{quantity}} визиток, бумага {{paper}}, печать {{print_color}}{{#lamination}}, ламинация {{lamination_type}} {{lamination_thickness}}{{/lamination}}{{#rounded_corners}}, скругление углов{{/rounded_corners}}{{#uv_lacquer}}, УФ-лак{{/uv_lacquer}}{{#comment}}. {{comment}}{{/comment}}',
  '500 визиток, бумага 300 гр мелованная матовая, печать 4+4, ламинация матовая 32 мкн',
  20
),
(
  'Полиграфия', 'Листовки', NULL,
  'production', 'Собственное производство', NULL,
  $json$[
    {"key":"format","label":"Формат","type":"select","required":true,"options":["А7","А6","А5","А4","А3","Свой размер"]},
    {"key":"custom_width_mm","label":"Ширина, мм","type":"number","required":true,"show_when":{"format":"Свой размер"}},
    {"key":"custom_height_mm","label":"Высота, мм","type":"number","required":true,"show_when":{"format":"Свой размер"}},
    {"key":"paper","label":"Бумага","type":"select","required":true,"options":["130 гр мелованная матовая","130 гр мелованная глянцевая","170 гр мелованная матовая","170 гр мелованная глянцевая"]},
    {"key":"print_color","label":"Цветность печати","type":"select","required":true,"options":["1+0","1+1","4+0","4+1","4+4"]},
    {"key":"perforation","label":"Перфорация","type":"checkbox","required":false},
    {"key":"creasing","label":"Биговка","type":"checkbox","required":false},
    {"key":"creasing_count","label":"Количество бигов","type":"number","required":true,"show_when":{"creasing":true}},
    {"key":"comment","label":"Комментарий к ТЗ","type":"textarea","required":false}
  ]$json$::jsonb,
  '{{quantity}} листовок {{format}}, бумага {{paper}}, печать {{print_color}}{{#perforation}}, перфорация{{/perforation}}{{#creasing}}, биговка {{creasing_count}} биг.{{/creasing}}{{#comment}}. {{comment}}{{/comment}}',
  '1000 листовок А5, бумага 170 гр мелованная глянцевая, печать 4+4',
  30
),
(
  'Полиграфия', 'Открытки', NULL,
  'production', 'Собственное производство', NULL,
  $json$[
    {"key":"format","label":"Формат","type":"select","required":true,"options":["А7","А6","А5","А4","А3","Свой размер"]},
    {"key":"custom_width_mm","label":"Ширина, мм","type":"number","required":true,"show_when":{"format":"Свой размер"}},
    {"key":"custom_height_mm","label":"Высота, мм","type":"number","required":true,"show_when":{"format":"Свой размер"}},
    {"key":"paper","label":"Бумага","type":"select","required":true,"options":["200 гр мелованная матовая","200 гр мелованная глянцевая","250 гр мелованная матовая","250 гр мелованная глянцевая","300 гр мелованная матовая","300 гр мелованная глянцевая"]},
    {"key":"print_color","label":"Цветность печати","type":"select","required":true,"options":["1+0","1+1","4+0","4+1","4+4"]},
    {"key":"rounded_corners","label":"Скруглить углы","type":"checkbox","required":false},
    {"key":"comment","label":"Комментарий к ТЗ","type":"textarea","required":false}
  ]$json$::jsonb,
  '{{quantity}} открыток {{format}}, бумага {{paper}}, печать {{print_color}}{{#rounded_corners}}, скругление углов{{/rounded_corners}}{{#comment}}. {{comment}}{{/comment}}',
  '100 открыток А6, бумага 300 гр мелованная глянцевая, печать 4+4',
  40
),
(
  'Полиграфия', 'Блокноты', NULL,
  'production', 'Собственное производство', NULL,
  $json$[
    {"key":"format","label":"Формат","type":"select","required":true,"options":["А6","А5","А4"]},
    {"key":"cover_print","label":"Печать обложки","type":"select","required":true,"options":["4+0","4+4"]},
    {"key":"back_print","label":"Печать задника","type":"select","required":true,"options":["Без печати","4+0","4+4"]},
    {"key":"inner_paper","label":"Внутренний блок","type":"select","required":true,"options":["80 гр офисная без запечатки","80 гр офисная 1+0","80 гр офисная 1+1"]},
    {"key":"inner_ruling","label":"Запечатка блока","type":"select","required":true,"options":["Без запечатки","Клетка","Линейка","По макету заказчика"]},
    {"key":"sheets_count","label":"Листов в блоке","type":"number","required":true,"default":40},
    {"key":"cover_lamination","label":"Ламинация обложки","type":"checkbox","required":false},
    {"key":"cover_lamination_type","label":"Тип ламинации обложки","type":"select","required":true,"options":["Матовая","Глянцевая","Софт-тач"],"show_when":{"cover_lamination":true}},
    {"key":"back_lamination","label":"Ламинация задника","type":"checkbox","required":false},
    {"key":"back_lamination_type","label":"Тип ламинации задника","type":"select","required":true,"options":["Матовая","Глянцевая","Софт-тач"],"show_when":{"back_lamination":true}},
    {"key":"intro_block","label":"Информационный блок перед внутренним блоком","type":"checkbox","required":false},
    {"key":"intro_sheets_count","label":"Листов инфоблока","type":"number","required":true,"show_when":{"intro_block":true}},
    {"key":"intro_print_color","label":"Цветность инфоблока","type":"select","required":true,"options":["1+0","1+1","4+0","4+1","4+4"],"show_when":{"intro_block":true}},
    {"key":"intro_paper","label":"Бумага инфоблока","type":"select","required":true,"options":["80 гр офисная","130 гр мелованная","170 гр мелованная","200 гр мелованная","250 гр мелованная","300 гр мелованная"],"show_when":{"intro_block":true}},
    {"key":"spring_side","label":"Пружина","type":"select","required":true,"options":["Сверху","Слева"]},
    {"key":"spring_color","label":"Цвет пружины","type":"select","required":true,"options":["Белая","Черная"]},
    {"key":"comment","label":"Комментарий к ТЗ","type":"textarea","required":false}
  ]$json$::jsonb,
  '{{quantity}} блокнотов {{format}}, обложка 300 гр {{cover_print}}, задник {{back_print}}, блок {{sheets_count}} л., {{inner_paper}}, {{inner_ruling}}, пружина {{spring_side}} {{spring_color}}{{#cover_lamination}}, ламинация обложки {{cover_lamination_type}}{{/cover_lamination}}{{#back_lamination}}, ламинация задника {{back_lamination_type}}{{/back_lamination}}{{#comment}}. {{comment}}{{/comment}}',
  '50 блокнотов А5, обложка 300 гр 4+0, блок 40 л., 80 гр офисная, клетка, пружина сверху белая',
  50
),
(
  'Полиграфия', 'Бейджи', NULL,
  'production', 'Собственное производство', NULL,
  $json$[
    {"key":"format","label":"Формат","type":"select","required":true,"options":["А7","А6","Свой размер"]},
    {"key":"custom_width_mm","label":"Ширина, мм","type":"number","required":true,"show_when":{"format":"Свой размер"}},
    {"key":"custom_height_mm","label":"Высота, мм","type":"number","required":true,"show_when":{"format":"Свой размер"}},
    {"key":"paper","label":"Бумага","type":"select","required":true,"default":"300 гр мелованная","options":["300 гр мелованная матовая","300 гр мелованная глянцевая"]},
    {"key":"print_color","label":"Цветность печати","type":"select","required":true,"options":["4+0","4+4"]},
    {"key":"lamination","label":"Ламинация","type":"checkbox","required":false},
    {"key":"lamination_type","label":"Тип ламинации","type":"select","required":true,"options":["Матовая","Глянцевая","Софт-тач"],"show_when":{"lamination":true}},
    {"key":"lamination_thickness","label":"Плотность ламинации","type":"select","required":true,"options":["32 мкн","125 мкн","250 мкн"],"show_when":{"lamination":true}},
    {"key":"rounded_corners","label":"Скруглить углы","type":"checkbox","required":false},
    {"key":"hole_type","label":"Тип отверстия","type":"select","required":true,"options":["Под карабин","Под два карабина","Под крокодил"]},
    {"key":"comment","label":"Комментарий к ТЗ","type":"textarea","required":false}
  ]$json$::jsonb,
  '{{quantity}} бейджей {{format}}, бумага {{paper}}, печать {{print_color}}, отверстие {{hole_type}}{{#lamination}}, ламинация {{lamination_type}} {{lamination_thickness}}{{/lamination}}{{#rounded_corners}}, скругление углов{{/rounded_corners}}{{#comment}}. {{comment}}{{/comment}}',
  '60 бейджей А6, бумага 300 гр, печать 4+4, отверстие под карабин',
  60
),
(
  'Полиграфия', 'Календари', NULL,
  'production', 'Собственное производство', NULL,
  $json$[
    {"key":"calendar_type","label":"Тип календаря","type":"select","required":true,"options":["Настенный","Настольный","Карманный"]},
    {"key":"wall_type","label":"Вид настенного календаря","type":"select","required":true,"options":["Перекидной","Отрывной"],"show_when":{"calendar_type":"Настенный"}},
    {"key":"format","label":"Формат","type":"select","required":true,"options":["100х70 мм","Свой размер"],"default":"100х70 мм","show_when":{"calendar_type":"Карманный"}},
    {"key":"custom_width_mm","label":"Ширина, мм","type":"number","required":true,"show_when":{"format":"Свой размер"}},
    {"key":"custom_height_mm","label":"Высота, мм","type":"number","required":true,"show_when":{"format":"Свой размер"}},
    {"key":"print_color","label":"Цветность печати","type":"select","required":true,"options":["1+0","1+1","4+0","4+1","4+4"]},
    {"key":"lamination_type","label":"Тип ламинации","type":"select","required":true,"options":["Матовая","Глянцевая"],"show_when":{"calendar_type":"Карманный"}},
    {"key":"rounded_corners","label":"Скруглить углы","type":"checkbox","required":false,"show_when":{"calendar_type":"Карманный"}},
    {"key":"comment","label":"Комментарий к ТЗ","type":"textarea","required":false}
  ]$json$::jsonb,
  '{{quantity}} календарей {{calendar_type}}{{#wall_type}} {{wall_type}}{{/wall_type}}, печать {{print_color}}{{#lamination_type}}, ламинация {{lamination_type}}{{/lamination_type}}{{#rounded_corners}}, скругление углов{{/rounded_corners}}{{#comment}}. {{comment}}{{/comment}}',
  '100 карманных календарей 100х70 мм, печать 4+4, ламинация матовая',
  70
),
(
  'Полиграфия', 'Закладки', NULL,
  'production', 'Собственное производство', NULL,
  $json$[
    {"key":"custom_width_mm","label":"Ширина, мм","type":"number","required":true},
    {"key":"custom_height_mm","label":"Высота, мм","type":"number","required":true},
    {"key":"print_color","label":"Цветность печати","type":"select","required":true,"options":["1+0","1+1","4+0","4+1","4+4"]},
    {"key":"lamination","label":"Ламинация","type":"checkbox","required":false},
    {"key":"lamination_type","label":"Тип ламинации","type":"select","required":true,"options":["Матовая","Глянцевая"],"show_when":{"lamination":true}},
    {"key":"rounded_corners","label":"Скруглить углы","type":"checkbox","required":false},
    {"key":"comment","label":"Комментарий к ТЗ","type":"textarea","required":false}
  ]$json$::jsonb,
  '{{quantity}} закладок {{custom_width_mm}}х{{custom_height_mm}} мм, печать {{print_color}}{{#lamination}}, ламинация {{lamination_type}}{{/lamination}}{{#rounded_corners}}, скругление углов{{/rounded_corners}}{{#comment}}. {{comment}}{{/comment}}',
  '200 закладок 50х180 мм, печать 4+4, ламинация глянцевая',
  80
),
(
  'Полиграфия', 'Брошюры', NULL,
  'production', 'Собственное производство', NULL,
  $json$[
    {"key":"cover_paper","label":"Бумага обложки","type":"select","required":true,"options":["80 гр офисная","130 гр мелованная","170 гр мелованная","200 гр мелованная","250 гр мелованная","300 гр мелованная","Дизайнерская","Крафт-бумага"]},
    {"key":"inner_paper","label":"Бумага внутреннего блока","type":"select","required":true,"options":["80 гр офисная","130 гр мелованная","170 гр мелованная","200 гр мелованная","250 гр мелованная","300 гр мелованная","Дизайнерская","Крафт-бумага"]},
    {"key":"pages_count","label":"Количество страниц блока","type":"number","required":true},
    {"key":"cover_print","label":"Цветность обложки","type":"select","required":true,"options":["1+0","1+1","4+0","4+1","4+4"]},
    {"key":"inner_print","label":"Цветность внутренних страниц","type":"select","required":true,"options":["1+0","1+1","4+0","4+1","4+4"]},
    {"key":"cover_lamination","label":"Ламинация обложки","type":"checkbox","required":false},
    {"key":"cover_lamination_type","label":"Тип ламинации обложки","type":"select","required":true,"options":["Матовая","Глянцевая","Софт-тач"],"show_when":{"cover_lamination":true}},
    {"key":"binding","label":"Брошюровка","type":"select","required":true,"options":["На скобы","На пружину","Без сборки"]},
    {"key":"comment","label":"Комментарий к ТЗ","type":"textarea","required":false}
  ]$json$::jsonb,
  '{{quantity}} брошюр, обложка {{cover_paper}} {{cover_print}}, блок {{pages_count}} стр., {{inner_paper}} {{inner_print}}, брошюровка {{binding}}{{#cover_lamination}}, ламинация обложки {{cover_lamination_type}}{{/cover_lamination}}{{#comment}}. {{comment}}{{/comment}}',
  '50 брошюр, обложка 300 гр 4+4, блок 24 стр. 130 гр 4+4, на скобы',
  90
),
(
  'Полиграфия', 'Буклеты', NULL,
  'production', 'Собственное производство', NULL,
  $json$[
    {"key":"format","label":"Формат","type":"select","required":true,"options":["А7","А6","А5","А4","А3","Свой размер"]},
    {"key":"custom_width_mm","label":"Ширина, мм","type":"number","required":true,"show_when":{"format":"Свой размер"}},
    {"key":"custom_height_mm","label":"Высота, мм","type":"number","required":true,"show_when":{"format":"Свой размер"}},
    {"key":"paper","label":"Бумага","type":"select","required":true,"options":["80 гр офисная","130 гр мелованная","170 гр мелованная","200 гр мелованная","250 гр мелованная","300 гр мелованная","Дизайнерская","Крафт-бумага"]},
    {"key":"print_color","label":"Цветность печати","type":"select","required":true,"options":["1+1","4+1","4+4"]},
    {"key":"fold_type","label":"Тип буклета","type":"select","required":true,"options":["Книжка","Евробуклет","Гармошка 2 бига","Окно","Гармошка 3 бига","Гармошка 4 бига","Гармошка 5 бигов","Гармошка 6 бигов","Нестандартный"]},
    {"key":"vertical_creases","label":"Вертикальных бигов","type":"number","required":true,"show_when":{"fold_type":"Нестандартный"}},
    {"key":"horizontal_creases","label":"Горизонтальных бигов","type":"number","required":true,"show_when":{"fold_type":"Нестандартный"}},
    {"key":"comment","label":"Комментарий к ТЗ","type":"textarea","required":false}
  ]$json$::jsonb,
  '{{quantity}} буклетов {{format}}, бумага {{paper}}, печать {{print_color}}, {{fold_type}}{{#comment}}. {{comment}}{{/comment}}',
  '500 буклетов А4, бумага 170 гр, печать 4+4, евробуклет',
  100
),
(
  'Баннеры', NULL, NULL,
  'production', 'Баннерная печать', NULL,
  $json$[
    {"key":"material","label":"Материал","type":"select","required":true,"options":["Баннерная ткань","Баннерная сетка","Блекаут"]},
    {"key":"width_mm","label":"Ширина, мм","type":"number","required":true},
    {"key":"height_mm","label":"Высота, мм","type":"number","required":true},
    {"key":"processing","label":"Обработка","type":"select","required":true,"options":["Без обработки","Проклейка","Люверсы","Проклейка и люверсы"]},
    {"key":"grommets_place","label":"Люверсы","type":"select","required":true,"options":["По периметру","По углам"],"show_when_any":[{"processing":"Люверсы"},{"processing":"Проклейка и люверсы"}]},
    {"key":"comment","label":"Комментарий к ТЗ","type":"textarea","required":false}
  ]$json$::jsonb,
  '{{quantity}} баннеров {{material}}, {{width_mm}}х{{height_mm}} мм, {{processing}}{{#grommets_place}} {{grommets_place}}{{/grommets_place}}{{#comment}}. {{comment}}{{/comment}}',
  '1 баннер баннерная ткань, 3000х2000 мм, проклейка и люверсы по периметру',
  110
),
(
  'ПВХ - таблички', NULL, NULL,
  'production', 'Печать табличек', NULL,
  $json$[
    {"key":"material","label":"Материал","type":"select","required":true,"options":["ПВХ 3 мм","ПВХ 5 мм","ПВХ 8 мм","ПВХ 10 мм"]},
    {"key":"format","label":"Размер","type":"select","required":true,"options":["А5","А4","А3","А2","А1","А0","Свой размер"]},
    {"key":"custom_width_mm","label":"Ширина, мм","type":"number","required":true,"show_when":{"format":"Свой размер"}},
    {"key":"custom_height_mm","label":"Высота, мм","type":"number","required":true,"show_when":{"format":"Свой размер"}},
    {"key":"folds","label":"Подвороты","type":"checkbox","required":false},
    {"key":"lamination_type","label":"Ламинация","type":"select","required":true,"options":["Матовая","Глянцевая"]},
    {"key":"pipe_holder","label":"Держатель под трубу","type":"checkbox","required":false},
    {"key":"mounting_tape","label":"Скотч для крепления","type":"checkbox","required":false},
    {"key":"comment","label":"Комментарий к ТЗ","type":"textarea","required":false}
  ]$json$::jsonb,
  '{{quantity}} табличек {{material}}, {{format}}, ламинация {{lamination_type}}{{#folds}}, с подворотами{{/folds}}{{#pipe_holder}}, держатель под трубу{{/pipe_holder}}{{#mounting_tape}}, скотч для крепления{{/mounting_tape}}{{#comment}}. {{comment}}{{/comment}}',
  '2 таблички ПВХ 5 мм, А3, ламинация матовая, скотч для крепления',
  120
),
(
  'Наклейки', 'Единичные наклейки', NULL,
  'production', 'Печать наклеек', NULL,
  $json$[
    {"key":"width_mm","label":"Ширина, мм","type":"number","required":true},
    {"key":"height_mm","label":"Высота, мм","type":"number","required":true},
    {"key":"film","label":"Пленка","type":"select","required":true,"options":["Прозрачная пленка","Глянцевая пленка","Матовая пленка","Блекаут пленка","Оракал в один цвет"]},
    {"key":"resin","label":"Заливка смолой","type":"checkbox","required":false},
    {"key":"transfer_film","label":"Накатка на монтажную пленку","type":"checkbox","required":false},
    {"key":"lamination","label":"Ламинация","type":"checkbox","required":false},
    {"key":"comment","label":"Комментарий к ТЗ","type":"textarea","required":false}
  ]$json$::jsonb,
  '{{quantity}} наклеек {{width_mm}}х{{height_mm}} мм, {{film}}{{#lamination}}, ламинация{{/lamination}}{{#resin}}, заливка смолой{{/resin}}{{#transfer_film}}, на монтажной пленке{{/transfer_film}}{{#comment}}. {{comment}}{{/comment}}',
  '100 наклеек 50х30 мм, глянцевая пленка, ламинация',
  130
),
(
  'Наклейки', 'Стикерпаки', NULL,
  'production', 'Печать наклеек', NULL,
  $json$[
    {"key":"format","label":"Размер листа","type":"select","required":true,"options":["А6","А5","А4","Свой размер"]},
    {"key":"custom_width_mm","label":"Ширина, мм","type":"number","required":true,"show_when":{"format":"Свой размер"}},
    {"key":"custom_height_mm","label":"Высота, мм","type":"number","required":true,"show_when":{"format":"Свой размер"}},
    {"key":"film","label":"Пленка","type":"select","required":true,"options":["Матовая пленка","Глянцевая пленка"]},
    {"key":"lamination","label":"Ламинация","type":"select","required":false,"options":["Без ламинации","Матовая ламинация","Глянцевая ламинация"]},
    {"key":"resin","label":"Заливка смолой","type":"checkbox","required":false},
    {"key":"comment","label":"Комментарий к ТЗ","type":"textarea","required":false}
  ]$json$::jsonb,
  '{{quantity}} стикерпаков {{format}}, {{film}}, {{lamination}}{{#resin}}, заливка смолой{{/resin}}{{#comment}}. {{comment}}{{/comment}}',
  '50 стикерпаков А5, матовая пленка, матовая ламинация',
  140
),
(
  'Наклейки', 'Наклейки на монтажке', NULL,
  'production', 'Плоттерная резка', NULL,
  $json$[
    {"key":"width_mm","label":"Ширина, мм","type":"number","required":true},
    {"key":"height_mm","label":"Высота, мм","type":"number","required":true},
    {"key":"sticker_color","label":"Цвет наклейки","type":"text","required":true},
    {"key":"comment","label":"Комментарий к ТЗ","type":"textarea","required":false}
  ]$json$::jsonb,
  '{{quantity}} наклеек на монтажке {{width_mm}}х{{height_mm}} мм, цвет {{sticker_color}}{{#comment}}. {{comment}}{{/comment}}',
  '10 наклеек на монтажке 300х100 мм, цвет белый',
  150
),
(
  'Наклейки', 'УФ-ДТФ', NULL,
  'production', 'УФ-ДТФ печать', NULL,
  $json$[
    {"key":"width_mm","label":"Ширина, мм","type":"number","required":true},
    {"key":"height_mm","label":"Высота, мм","type":"number","required":true},
    {"key":"comment","label":"Комментарий к ТЗ","type":"textarea","required":false}
  ]$json$::jsonb,
  '{{quantity}} УФ-ДТФ наклеек {{width_mm}}х{{height_mm}} мм{{#comment}}. {{comment}}{{/comment}}',
  '100 УФ-ДТФ наклеек 80х40 мм',
  160
),
(
  'Сувениры, мерч', NULL, 'УФ-печать',
  'production', 'Поставщик заготовки при необходимости', 'УФ-печать',
  $json$[
    {"key":"application_size","label":"Размер печати","type":"text","required":true},
    {"key":"comment","label":"Комментарий к ТЗ","type":"textarea","required":false}
  ]$json$::jsonb,
  '{{product_name}} с УФ-печатью, размер нанесения {{application_size}}{{#comment}}. {{comment}}{{/comment}}',
  'Ежедневники с УФ-печатью, размер нанесения 90х50 мм',
  170
),
(
  'Сувениры, мерч', NULL, 'Гравировка',
  'production', 'Поставщик заготовки при необходимости', 'Гравировка',
  $json$[
    {"key":"engraving_size","label":"Размер гравировки","type":"text","required":true},
    {"key":"engraving_type","label":"Тип гравировки","type":"select","required":true,"options":["Прямая","Круговая"]},
    {"key":"comment","label":"Комментарий к ТЗ","type":"textarea","required":false}
  ]$json$::jsonb,
  '{{product_name}} с гравировкой {{engraving_type}}, размер {{engraving_size}}{{#comment}}. {{comment}}{{/comment}}',
  'Ручки с гравировкой прямая, размер 50х8 мм',
  180
),
(
  'Сувениры, мерч', NULL, 'Сублимация',
  'production', 'Поставщик заготовки при необходимости', 'Сублимация',
  $json$[
    {"key":"sublimation_type","label":"Тип сублимации","type":"select","required":true,"options":["Плоская","Кружки"]},
    {"key":"comment","label":"Комментарий к ТЗ","type":"textarea","required":false}
  ]$json$::jsonb,
  '{{product_name}}, сублимация {{sublimation_type}}{{#comment}}. {{comment}}{{/comment}}',
  'Кружки, сублимация кружки',
  190
),
(
  'Сувениры, мерч', NULL, 'Шелкография',
  'screen_printing', 'Поставщик заготовки при необходимости', 'Шелкография',
  $json$[
    {"key":"application_size","label":"Размер нанесения","type":"text","required":true},
    {"key":"colors_count","label":"Количество цветов","type":"number","required":true},
    {"key":"comment","label":"Комментарий к ТЗ","type":"textarea","required":false}
  ]$json$::jsonb,
  '{{product_name}}, шелкография {{application_size}}, {{colors_count}} цвет(а){{#comment}}. {{comment}}{{/comment}}',
  'Ручки, шелкография 60х8 мм, 1 цвет',
  200
),
(
  'Сувениры, мерч', NULL, 'Тиснение',
  'production', 'Поставщик заготовки при необходимости', 'Тиснение',
  $json$[
    {"key":"application_size","label":"Размер тиснения","type":"text","required":true},
    {"key":"comment","label":"Комментарий к ТЗ","type":"textarea","required":false}
  ]$json$::jsonb,
  '{{product_name}}, тиснение {{application_size}}{{#comment}}. {{comment}}{{/comment}}',
  'Ежедневники, тиснение 90х50 мм',
  210
),
(
  'Сувениры, мерч', NULL, 'УФ-ДТФ',
  'production', 'Поставщик заготовки при необходимости', 'УФ-ДТФ',
  $json$[
    {"key":"application_size","label":"Размер нанесения","type":"text","required":true},
    {"key":"comment","label":"Комментарий к ТЗ","type":"textarea","required":false}
  ]$json$::jsonb,
  '{{product_name}}, УФ-ДТФ {{application_size}}{{#comment}}. {{comment}}{{/comment}}',
  'Термосы, УФ-ДТФ 80х40 мм',
  220
),
(
  'Упаковка', 'Пакеты бумажные', NULL,
  'production', 'Поставщик упаковки', 'Нанесение',
  $json$[
    {"key":"print_method","label":"Способ печати","type":"select","required":true,"options":["УФ-печать","Шелкография"]},
    {"key":"application_size","label":"Размер печати","type":"text","required":true},
    {"key":"colors_count","label":"Количество цветов","type":"number","required":true,"show_when":{"print_method":"Шелкография"}},
    {"key":"comment","label":"Комментарий к ТЗ","type":"textarea","required":false}
  ]$json$::jsonb,
  '{{product_name}}, {{print_method}}, размер печати {{application_size}}{{#colors_count}}, {{colors_count}} цвет(а){{/colors_count}}{{#comment}}. {{comment}}{{/comment}}',
  'Пакеты бумажные, шелкография, размер печати 120х80 мм, 1 цвет',
  230
),
(
  'Упаковка', 'Пакеты ПВД', NULL,
  'production', 'Поставщик упаковки', 'Нанесение',
  $json$[
    {"key":"print_method","label":"Способ печати","type":"select","required":true,"options":["УФ-печать","Шелкография"]},
    {"key":"application_size","label":"Размер печати","type":"text","required":true},
    {"key":"colors_count","label":"Количество цветов","type":"number","required":true,"show_when":{"print_method":"Шелкография"}},
    {"key":"comment","label":"Комментарий к ТЗ","type":"textarea","required":false}
  ]$json$::jsonb,
  '{{product_name}}, {{print_method}}, размер печати {{application_size}}{{#colors_count}}, {{colors_count}} цвет(а){{/colors_count}}{{#comment}}. {{comment}}{{/comment}}',
  'Пакеты ПВД, УФ-печать, размер печати 100х100 мм',
  240
),
(
  'Упаковка', 'Коробки', NULL,
  'production', 'Поставщик упаковки', 'Нанесение',
  $json$[
    {"key":"print_method","label":"Способ печати","type":"select","required":true,"options":["УФ-печать","Шелкография"]},
    {"key":"application_size","label":"Размер печати","type":"text","required":true},
    {"key":"colors_count","label":"Количество цветов","type":"number","required":true,"show_when":{"print_method":"Шелкография"}},
    {"key":"comment","label":"Комментарий к ТЗ","type":"textarea","required":false}
  ]$json$::jsonb,
  '{{product_name}}, {{print_method}}, размер печати {{application_size}}{{#colors_count}}, {{colors_count}} цвет(а){{/colors_count}}{{#comment}}. {{comment}}{{/comment}}',
  'Коробки, шелкография, размер печати 150х90 мм, 2 цвета',
  250
),
(
  'Текстиль', NULL, 'Шелкография',
  'screen_printing', 'Поставщик текстильной заготовки', 'Шелкография',
  $json$[
    {"key":"prints_count","label":"Количество принтов","type":"number","required":true,"min":1,"max":4},
    {"key":"print_1_size","label":"Размер нанесения 1","type":"select","required":true,"options":["А7","А6","А5","А4","А3"],"show_when_min":{"prints_count":1}},
    {"key":"print_1_colors","label":"Цветов нанесения 1","type":"number","required":true,"show_when_min":{"prints_count":1}},
    {"key":"print_2_size","label":"Размер нанесения 2","type":"select","required":true,"options":["А7","А6","А5","А4","А3"],"show_when_min":{"prints_count":2}},
    {"key":"print_2_colors","label":"Цветов нанесения 2","type":"number","required":true,"show_when_min":{"prints_count":2}},
    {"key":"print_3_size","label":"Размер нанесения 3","type":"select","required":true,"options":["А7","А6","А5","А4","А3"],"show_when_min":{"prints_count":3}},
    {"key":"print_3_colors","label":"Цветов нанесения 3","type":"number","required":true,"show_when_min":{"prints_count":3}},
    {"key":"print_4_size","label":"Размер нанесения 4","type":"select","required":true,"options":["А7","А6","А5","А4","А3"],"show_when_min":{"prints_count":4}},
    {"key":"print_4_colors","label":"Цветов нанесения 4","type":"number","required":true,"show_when_min":{"prints_count":4}},
    {"key":"comment","label":"Комментарий к ТЗ","type":"textarea","required":false}
  ]$json$::jsonb,
  '{{product_name}}, {{quantity}} шт., шелкография, {{prints_count}} принт(а){{#comment}}. {{comment}}{{/comment}}',
  'Футболки, 50 шт., шелкография, 2 принта',
  260
),
(
  'Текстиль', NULL, 'Шелкография с трансфером',
  'screen_printing', 'Поставщик текстильной заготовки', 'Шелкография с трансфером',
  $json$[
    {"key":"prints_count","label":"Количество принтов","type":"number","required":true,"min":1,"max":4},
    {"key":"print_size","label":"Размеры принтов","type":"repeatable_size_color","required":true,"count_from":"prints_count","size_options":["А7","А6","А5","А4","А3"]},
    {"key":"comment","label":"Комментарий к ТЗ","type":"textarea","required":false}
  ]$json$::jsonb,
  '{{product_name}}, {{quantity}} шт., шелкография с трансфером, {{prints_count}} принт(а){{#comment}}. {{comment}}{{/comment}}',
  'Поло, 30 шт., шелкография с трансфером, 1 принт А4',
  270
),
(
  'Текстиль', NULL, 'Вышивка',
  'production', 'Поставщик текстильной заготовки', 'Вышивка',
  $json$[
    {"key":"prints_count","label":"Количество вышивок","type":"number","required":true,"min":1,"max":4},
    {"key":"print_size","label":"Размеры вышивок","type":"repeatable_size_color","required":true,"count_from":"prints_count","size_options":["А7","А6","А5","А4","А3"],"max_colors":10},
    {"key":"comment","label":"Комментарий к ТЗ","type":"textarea","required":false}
  ]$json$::jsonb,
  '{{product_name}}, {{quantity}} шт., вышивка, {{prints_count}} нанесение(я){{#comment}}. {{comment}}{{/comment}}',
  'Кепки, 20 шт., вышивка, 1 нанесение, 4 цвета',
  280
),
(
  'Текстиль', NULL, 'Сублимация',
  'production', 'Поставщик текстильной заготовки', 'Сублимация',
  $json$[
    {"key":"application_size","label":"Размер нанесения","type":"text","required":true},
    {"key":"prints_count","label":"Количество принтов","type":"number","required":true},
    {"key":"comment","label":"Комментарий к ТЗ","type":"textarea","required":false}
  ]$json$::jsonb,
  '{{product_name}}, {{quantity}} шт., сублимация {{application_size}}, {{prints_count}} принт(а){{#comment}}. {{comment}}{{/comment}}',
  'Футболки, 30 шт., сублимация А4, 1 принт',
  290
),
(
  'Текстиль', NULL, 'ДТФ',
  'production', 'Поставщик текстильной заготовки', 'ДТФ',
  $json$[
    {"key":"format","label":"Размер нанесения","type":"select","required":true,"options":["А7","А6","А5","А4","А3","Свой размер"]},
    {"key":"custom_width_mm","label":"Ширина, мм","type":"number","required":true,"show_when":{"format":"Свой размер"}},
    {"key":"custom_height_mm","label":"Высота, мм","type":"number","required":true,"show_when":{"format":"Свой размер"}},
    {"key":"comment","label":"Комментарий к ТЗ","type":"textarea","required":false}
  ]$json$::jsonb,
  '{{product_name}}, {{quantity}} шт., ДТФ {{format}}{{#comment}}. {{comment}}{{/comment}}',
  'Футболки, 50 шт., ДТФ А4',
  300
),
(
  'Текстиль', NULL, 'Пленка',
  'production', 'Поставщик текстильной заготовки', 'Пленка',
  $json$[
    {"key":"application_size","label":"Размер нанесения","type":"text","required":true},
    {"key":"film_color","label":"Цвет пленки","type":"text","required":true},
    {"key":"comment","label":"Комментарий к ТЗ","type":"textarea","required":false}
  ]$json$::jsonb,
  '{{product_name}}, {{quantity}} шт., пленка {{application_size}}, цвет {{film_color}}{{#comment}}. {{comment}}{{/comment}}',
  'Футболки, 20 шт., пленка А4, цвет белый',
  310
),
(
  'Текстиль', NULL, 'Пошив',
  'production', 'Поставщик текстильной заготовки', 'Пошив',
  $json$[
    {"key":"sizes_grid","label":"Размерная сетка","type":"textarea","required":true},
    {"key":"comment","label":"Комментарий к ТЗ","type":"textarea","required":false}
  ]$json$::jsonb,
  '{{product_name}}, {{quantity}} шт., пошив. Размерная сетка: {{sizes_grid}}{{#comment}}. {{comment}}{{/comment}}',
  'Футболки, 50 шт., пошив. Размерная сетка: S-10, M-20, L-20',
  320
),
(
  'Ткани', 'Флаги стандартные', NULL,
  'production', 'Печать по ткани', NULL,
  $json$[
    {"key":"material","label":"Материал","type":"select","required":true,"options":["Шелк","Атлас","Габардин","Блекаут","Сетка"]},
    {"key":"size","label":"Размер","type":"select","required":true,"options":["12х18 см","15х22 см","20х30 см","30х40 см","40х60 см","50х75 см","60х90 см","70х105 см","90х135 см","100х150 см","100х200 см","140х210 см","150х225 см","200х300 см"]},
    {"key":"sides","label":"Сторонность","type":"select","required":true,"options":["Односторонний","Двусторонний"]},
    {"key":"impregnation","label":"Пропитка","type":"checkbox","required":false},
    {"key":"comment","label":"Комментарий к ТЗ","type":"textarea","required":false}
  ]$json$::jsonb,
  '{{quantity}} флагов {{size}}, {{material}}, {{sides}}{{#impregnation}}, с пропиткой{{/impregnation}}{{#comment}}. {{comment}}{{/comment}}',
  '10 флагов 60х90 см, габардин, односторонний',
  330
),
(
  'Ткани', 'Флаги нестандартные', NULL,
  'production', 'Печать по ткани', NULL,
  $json$[
    {"key":"material","label":"Материал","type":"select","required":true,"options":["Шелк","Атлас","Габардин","Блекаут","Сетка"]},
    {"key":"width_mm","label":"Ширина, мм","type":"number","required":true},
    {"key":"height_mm","label":"Высота, мм","type":"number","required":true},
    {"key":"sides","label":"Сторонность","type":"select","required":true,"options":["Односторонний","Двусторонний"]},
    {"key":"impregnation","label":"Пропитка","type":"checkbox","required":false},
    {"key":"comment","label":"Комментарий к ТЗ","type":"textarea","required":false}
  ]$json$::jsonb,
  '{{quantity}} флагов {{width_mm}}х{{height_mm}} мм, {{material}}, {{sides}}{{#impregnation}}, с пропиткой{{/impregnation}}{{#comment}}. {{comment}}{{/comment}}',
  '2 флага 1200х800 мм, шелк, двусторонний',
  340
),
(
  'Ткани', 'Флаги для виндеров', NULL,
  'production', 'Печать по ткани', NULL,
  $json$[
    {"key":"material","label":"Материал","type":"select","required":true,"options":["Шелк","Габардин","Сетка"]},
    {"key":"winder_model","label":"Модель виндера","type":"select","required":true,"options":["Флекс","Парус","Капля","Бриз","Моби"]},
    {"key":"winder_size","label":"Размер виндера","type":"select","required":true,"options":["2,1 м","2,5 м","3 м","3,7 м","4,2 м","5 м","6 м"]},
    {"key":"comment","label":"Комментарий к ТЗ","type":"textarea","required":false}
  ]$json$::jsonb,
  '{{quantity}} флагов для виндера {{winder_model}} {{winder_size}}, {{material}}{{#comment}}. {{comment}}{{/comment}}',
  '5 флагов для виндера Капля 3 м, шелк',
  350
),
(
  'Ткани', 'Банданы', NULL,
  'production', 'Печать по ткани', NULL,
  $json$[
    {"key":"material","label":"Материал","type":"select","required":true,"options":["Шелк","Габардин","Атлас","Свой выбор"]},
    {"key":"custom_material","label":"Материал","type":"text","required":true,"show_when":{"material":"Свой выбор"}},
    {"key":"shape","label":"Форма","type":"select","required":true,"options":["Треугольная","Прямоугольная"]},
    {"key":"size","label":"Размер","type":"select","required":true,"options":["60х60 см","70х70 см","Галстук 100х30 см"]},
    {"key":"edge_processing","label":"Обработка края","type":"select","required":true,"options":["Горячий рез","Краевка","Оверлок","Американка"]},
    {"key":"comment","label":"Комментарий к ТЗ","type":"textarea","required":false}
  ]$json$::jsonb,
  '{{quantity}} бандан {{shape}}, {{size}}, {{material}}, край {{edge_processing}}{{#comment}}. {{comment}}{{/comment}}',
  '30 бандан треугольных, 60х60 см, атлас, край оверлок',
  360
),
(
  'Конструкции', 'Ролап', NULL,
  'production', 'Печать баннера', NULL,
  $json$[
    {"key":"rollup_type","label":"Тип работ","type":"select","required":true,"options":["Замена полотна в конструкции заказчика","Конструкция с баннером"]},
    {"key":"size","label":"Размер","type":"select","required":true,"options":["85х200 см","100х200 см","Свой размер"],"show_when":{"rollup_type":"Конструкция с баннером"}},
    {"key":"banner_width_mm","label":"Ширина баннера, мм","type":"number","required":true,"show_when_any":[{"rollup_type":"Замена полотна в конструкции заказчика"},{"size":"Свой размер"}]},
    {"key":"banner_height_mm","label":"Высота баннера, мм","type":"number","required":true,"show_when_any":[{"rollup_type":"Замена полотна в конструкции заказчика"},{"size":"Свой размер"}]},
    {"key":"comment","label":"Комментарий к ТЗ","type":"textarea","required":false}
  ]$json$::jsonb,
  '{{quantity}} ролап(ов), {{rollup_type}}{{#size}}, размер {{size}}{{/size}}{{#banner_width_mm}}, баннер {{banner_width_mm}}х{{banner_height_mm}} мм{{/banner_width_mm}}{{#comment}}. {{comment}}{{/comment}}',
  '1 ролап, конструкция с баннером, размер 85х200 см',
  370
),
(
  'Конструкции', 'Виндер', NULL,
  'production', 'Печать по ткани', NULL,
  $json$[
    {"key":"winder_size","label":"Размер виндера","type":"select","required":true,"options":["2,1 м","2,5 м","3 м","3,7 м","4,2 м","5 м","6 м"]},
    {"key":"material","label":"Ткань","type":"select","required":true,"options":["Шелк","Габардин","Сетка"]},
    {"key":"winder_model","label":"Тип виндера","type":"select","required":true,"options":["Флекс","Парус","Капля","Бриз","Моби"]},
    {"key":"base_type","label":"Тип основания","type":"select","required":true,"options":["Металлическое","Наливное","Под плитку"]},
    {"key":"comment","label":"Комментарий к ТЗ","type":"textarea","required":false}
  ]$json$::jsonb,
  '{{quantity}} виндер(ов) {{winder_model}} {{winder_size}}, ткань {{material}}, основание {{base_type}}{{#comment}}. {{comment}}{{/comment}}',
  '2 виндера Капля 3 м, ткань шелк, основание наливное',
  380
),
(
  'Конструкции', 'Джокер', NULL,
  'production', 'Печать баннера', 'Монтаж',
  $json$[
    {"key":"size","label":"Размер конструкции","type":"select","required":true,"options":["2х2 м","2,5х2 м","3х2 м","Свой размер"]},
    {"key":"custom_width_mm","label":"Ширина, мм","type":"number","required":true,"show_when":{"size":"Свой размер"}},
    {"key":"custom_height_mm","label":"Высота, мм","type":"number","required":true,"show_when":{"size":"Свой размер"}},
    {"key":"comment","label":"Комментарий к ТЗ","type":"textarea","required":false}
  ]$json$::jsonb,
  '{{quantity}} конструкций Джокер {{size}}{{#custom_width_mm}} {{custom_width_mm}}х{{custom_height_mm}} мм{{/custom_width_mm}}{{#comment}}. {{comment}}{{/comment}}',
  '1 конструкция Джокер 3х2 м',
  390
),
(
  'Конструкции', 'Брус', NULL,
  'production', 'Печать баннера', 'Монтаж',
  $json$[
    {"key":"width_mm","label":"Ширина, мм","type":"number","required":true},
    {"key":"height_mm","label":"Высота, мм","type":"number","required":true},
    {"key":"need_slopes","label":"Нужны откосы","type":"checkbox","required":false},
    {"key":"need_weights","label":"Нужны пригрузы","type":"checkbox","required":false},
    {"key":"our_mounting","label":"Наш монтаж","type":"checkbox","required":false},
    {"key":"comment","label":"Комментарий к ТЗ","type":"textarea","required":false}
  ]$json$::jsonb,
  '{{quantity}} конструкций на брусе {{width_mm}}х{{height_mm}} мм{{#need_slopes}}, нужны откосы{{/need_slopes}}{{#need_weights}}, нужны пригрузы{{/need_weights}}{{#our_mounting}}, наш монтаж{{/our_mounting}}{{#comment}}. {{comment}}{{/comment}}',
  '1 конструкция на брусе 3000х2000 мм, нужны пригрузы, наш монтаж',
  400
),
(
  'Изделия из акрила и фанеры', 'Брелки', 'УФ-печать',
  'production', 'Лазерная резка / УФ-печать', NULL,
  $json$[
    {"key":"width_mm","label":"Ширина, мм","type":"number","required":true},
    {"key":"height_mm","label":"Высота, мм","type":"number","required":true},
    {"key":"material_thickness","label":"Толщина материала","type":"select","required":true,"options":["3 мм","5 мм","8 мм","10 мм"]},
    {"key":"hardware","label":"Фурнитура","type":"select","required":true,"options":["Кольцо","Цепочка с кольцом","Прочее"]},
    {"key":"hardware_comment","label":"Фурнитура: прочее","type":"text","required":true,"show_when":{"hardware":"Прочее"}},
    {"key":"front_print","label":"Печать с лицевой стороны","type":"checkbox","required":false},
    {"key":"back_mirror_print","label":"Печать с обратной стороны в зеркале","type":"checkbox","required":false},
    {"key":"white_underbase","label":"Белая подложка","type":"checkbox","required":false},
    {"key":"print_layers","label":"Количество слоев","type":"select","required":true,"options":["1 слой","2 слоя","3 слоя"]},
    {"key":"comment","label":"Комментарий к ТЗ","type":"textarea","required":false}
  ]$json$::jsonb,
  '{{quantity}} брелков {{width_mm}}х{{height_mm}} мм, толщина {{material_thickness}}, фурнитура {{hardware}}, УФ-печать {{print_layers}}{{#white_underbase}}, с подложкой{{/white_underbase}}{{#comment}}. {{comment}}{{/comment}}',
  '100 брелков 50х30 мм, толщина 3 мм, фурнитура кольцо, УФ-печать 2 слоя с подложкой',
  410
),
(
  'Изделия из акрила и фанеры', 'Значки', 'УФ-печать',
  'production', 'Лазерная резка / УФ-печать', NULL,
  $json$[
    {"key":"width_mm","label":"Ширина, мм","type":"number","required":true},
    {"key":"height_mm","label":"Высота, мм","type":"number","required":true},
    {"key":"material_thickness","label":"Толщина материала","type":"select","required":true,"options":["3 мм","5 мм","8 мм","10 мм"]},
    {"key":"mount_type","label":"Способ крепления","type":"select","required":true,"options":["Булавка","Цанга","Магнит"]},
    {"key":"front_print","label":"Печать с лицевой стороны","type":"checkbox","required":false},
    {"key":"back_mirror_print","label":"Печать с обратной стороны в зеркале","type":"checkbox","required":false},
    {"key":"white_underbase","label":"Белая подложка","type":"checkbox","required":false},
    {"key":"print_layers","label":"Количество слоев","type":"select","required":true,"options":["1 слой","2 слоя","3 слоя"]},
    {"key":"comment","label":"Комментарий к ТЗ","type":"textarea","required":false}
  ]$json$::jsonb,
  '{{quantity}} значков {{width_mm}}х{{height_mm}} мм, толщина {{material_thickness}}, крепление {{mount_type}}, УФ-печать {{print_layers}}{{#white_underbase}}, с подложкой{{/white_underbase}}{{#comment}}. {{comment}}{{/comment}}',
  '50 значков 40х40 мм, толщина 3 мм, крепление магнит, УФ-печать 2 слоя',
  420
),
(
  'Изделия из акрила и фанеры', 'Магниты', 'УФ-печать',
  'production', 'Лазерная резка / УФ-печать', NULL,
  $json$[
    {"key":"width_mm","label":"Ширина, мм","type":"number","required":true},
    {"key":"height_mm","label":"Высота, мм","type":"number","required":true},
    {"key":"material_thickness","label":"Толщина материала","type":"select","required":true,"options":["3 мм","5 мм","8 мм","10 мм"]},
    {"key":"front_print","label":"Печать с лицевой стороны","type":"checkbox","required":false},
    {"key":"back_mirror_print","label":"Печать с обратной стороны в зеркале","type":"checkbox","required":false},
    {"key":"white_underbase","label":"Белая подложка","type":"checkbox","required":false},
    {"key":"print_layers","label":"Количество слоев","type":"select","required":true,"options":["1 слой","2 слоя","3 слоя"]},
    {"key":"comment","label":"Комментарий к ТЗ","type":"textarea","required":false}
  ]$json$::jsonb,
  '{{quantity}} магнитов {{width_mm}}х{{height_mm}} мм, толщина {{material_thickness}}, УФ-печать {{print_layers}}{{#white_underbase}}, с подложкой{{/white_underbase}}{{#comment}}. {{comment}}{{/comment}}',
  '100 магнитов 70х50 мм, толщина 3 мм, УФ-печать 2 слоя',
  430
),
(
  'Изделия из акрила и фанеры', 'Стелы', 'Гравировка',
  'production', 'Лазерная резка / гравировка', NULL,
  $json$[
    {"key":"width_mm","label":"Ширина, мм","type":"number","required":true},
    {"key":"height_mm","label":"Высота, мм","type":"number","required":true},
    {"key":"material_thickness","label":"Толщина материала","type":"select","required":true,"options":["3 мм","5 мм","8 мм","10 мм"]},
    {"key":"comment","label":"Комментарий к ТЗ","type":"textarea","required":false}
  ]$json$::jsonb,
  '{{quantity}} стел {{width_mm}}х{{height_mm}} мм, толщина {{material_thickness}}, гравировка{{#comment}}. {{comment}}{{/comment}}',
  '1 стела 200х150 мм, толщина 8 мм, гравировка',
  440
);

INSERT INTO _tz_constructor_seed (
  category_name, subcategory_name, application_method_name,
  route_area, contractor_1_role, contractor_2_role,
  fields, template, example, sort
)
SELECT
  'Нанесение', NULL, method_name,
  CASE WHEN method_name IN ('Шелкография', 'Шелкография с трансфером') THEN 'screen_printing' ELSE 'production' END,
  NULL,
  method_name,
  CASE
    WHEN method_name = 'Вышивка' THEN $json$[
      {"key":"application_size","label":"Размер нанесения","type":"text","required":true},
      {"key":"colors_count","label":"Количество цветов вышивки","type":"number","required":true,"max":10},
      {"key":"comment","label":"Комментарий к ТЗ","type":"textarea","required":false}
    ]$json$::jsonb
    ELSE $json$[
      {"key":"application_size","label":"Размер нанесения","type":"text","required":true},
      {"key":"comment","label":"Комментарий к ТЗ","type":"textarea","required":false}
    ]$json$::jsonb
  END,
  CASE
    WHEN method_name = 'Вышивка' THEN '{{product_name}}, вышивка {{application_size}}, {{colors_count}} цвет(а){{#comment}}. {{comment}}{{/comment}}'
    ELSE '{{product_name}}, ' || method_name || ', размер нанесения {{application_size}}{{#comment}}. {{comment}}{{/comment}}'
  END,
  method_name || ': размер нанесения 90х50 мм',
  500 + rn
FROM (
  SELECT method_name, row_number() OVER () AS rn
  FROM (VALUES
    ('Цифровая печать'), ('Струйная печать'), ('Гравировка'), ('Шелкография'),
    ('Тиснение'), ('Сублимация'), ('УФ-печать'), ('УФ-ДТФ печать'),
    ('ДТФ-печать'), ('Шелкография с трансфером'), ('Вышивка')
  ) AS v(method_name)
) AS methods;

DELETE FROM tz_constructor_specs t
USING _tz_constructor_seed s
WHERE t.category_name = s.category_name
  AND COALESCE(t.subcategory_name, '') = COALESCE(s.subcategory_name, '')
  AND COALESCE(t.application_method_name, '') = COALESCE(s.application_method_name, '');

INSERT INTO tz_constructor_specs (
  category, subcategory, application_method,
  category_name, subcategory_name, application_method_name,
  route_area, contractor_1_role, contractor_2_role,
  fields, template, example, sort
)
SELECT
  pc.id,
  ps.id,
  pam.id,
  s.category_name,
  s.subcategory_name,
  s.application_method_name,
  s.route_area,
  s.contractor_1_role,
  s.contractor_2_role,
  s.fields,
  s.template,
  s.example,
  s.sort
FROM _tz_constructor_seed s
LEFT JOIN product_categories pc ON pc.name = s.category_name
LEFT JOIN product_subcategories ps
  ON ps.category = pc.id
 AND ps.name = s.subcategory_name
LEFT JOIN LATERAL (
  SELECT pam.id
  FROM product_application_methods pam
  WHERE pam.name = s.application_method_name
    AND (pam.category = pc.id OR pam.category IS NULL)
  ORDER BY CASE WHEN pam.category = pc.id THEN 0 ELSE 1 END, pam.id
  LIMIT 1
) pam ON true
ORDER BY s.sort;

INSERT INTO directus_collections (collection, icon, note, hidden, singleton, translations, sort)
VALUES (
  'tz_constructor_specs',
  'dynamic_form',
  'Dynamic technical task constructor rules.',
  false,
  false,
  json_build_array(json_build_object('language','ru-RU','translation','Конструктор ТЗ')),
  48
)
ON CONFLICT (collection) DO UPDATE SET
  icon = EXCLUDED.icon,
  note = EXCLUDED.note,
  hidden = false,
  translations = EXCLUDED.translations,
  sort = EXCLUDED.sort;

DELETE FROM directus_fields WHERE collection = 'tz_constructor_specs';

INSERT INTO directus_fields (
  collection, field, special, interface, options, display, display_options,
  readonly, hidden, sort, width, translations, note, required, searchable
) VALUES
  ('tz_constructor_specs','id',NULL,'input',NULL,NULL,NULL,true,true,1,'half',json_build_array(json_build_object('language','ru-RU','translation','ID')),NULL,false,true),
  ('tz_constructor_specs','category','m2o','select-dropdown-m2o','{"template":"{{name}}"}'::json,'related-values','{"template":"{{name}}"}'::json,false,false,2,'half',json_build_array(json_build_object('language','ru-RU','translation','Категория')),NULL,false,true),
  ('tz_constructor_specs','subcategory','m2o','select-dropdown-m2o','{"template":"{{name}}"}'::json,'related-values','{"template":"{{name}}"}'::json,false,false,3,'half',json_build_array(json_build_object('language','ru-RU','translation','Подкатегория')),NULL,false,true),
  ('tz_constructor_specs','application_method','m2o','select-dropdown-m2o','{"template":"{{name}}"}'::json,'related-values','{"template":"{{name}}"}'::json,false,false,4,'half',json_build_array(json_build_object('language','ru-RU','translation','Вид нанесения')),NULL,false,true),
  ('tz_constructor_specs','category_name',NULL,'input',NULL,NULL,NULL,false,false,5,'half',json_build_array(json_build_object('language','ru-RU','translation','Категория (текст)')),NULL,true,true),
  ('tz_constructor_specs','subcategory_name',NULL,'input',NULL,NULL,NULL,false,false,6,'half',json_build_array(json_build_object('language','ru-RU','translation','Подкатегория (текст)')),NULL,false,true),
  ('tz_constructor_specs','application_method_name',NULL,'input',NULL,NULL,NULL,false,false,7,'half',json_build_array(json_build_object('language','ru-RU','translation','Вид нанесения (текст)')),NULL,false,true),
  ('tz_constructor_specs','route_area',NULL,'select-dropdown','{"choices":[{"text":"Производство","value":"production"},{"text":"Шелкография","value":"screen_printing"},{"text":"Подрядчик","value":"contractor"}]}'::json,'labels',NULL,false,false,8,'half',json_build_array(json_build_object('language','ru-RU','translation','Участок')),NULL,false,true),
  ('tz_constructor_specs','contractor_1_role',NULL,'input',NULL,NULL,NULL,false,false,9,'half',json_build_array(json_build_object('language','ru-RU','translation','Роль подрядчика 1')),NULL,false,true),
  ('tz_constructor_specs','contractor_2_role',NULL,'input',NULL,NULL,NULL,false,false,10,'half',json_build_array(json_build_object('language','ru-RU','translation','Роль подрядчика 2')),NULL,false,true),
  ('tz_constructor_specs','fields','cast-json','input-code','{"language":"json"}'::json,NULL,NULL,false,false,11,'full',json_build_array(json_build_object('language','ru-RU','translation','Поля конструктора')),NULL,true,true),
  ('tz_constructor_specs','template',NULL,'input-multiline',NULL,NULL,NULL,false,false,12,'full',json_build_array(json_build_object('language','ru-RU','translation','Шаблон ТЗ')),NULL,true,true),
  ('tz_constructor_specs','example',NULL,'input-multiline',NULL,NULL,NULL,false,false,13,'full',json_build_array(json_build_object('language','ru-RU','translation','Пример')),NULL,false,true),
  ('tz_constructor_specs','active','cast-boolean','boolean',NULL,'boolean',NULL,false,false,14,'half',json_build_array(json_build_object('language','ru-RU','translation','Активно')),NULL,false,true),
  ('tz_constructor_specs','sort',NULL,'input',NULL,NULL,NULL,false,false,15,'half',json_build_array(json_build_object('language','ru-RU','translation','Сортировка')),NULL,false,true),
  ('tz_constructor_specs','updated_at',NULL,'datetime',NULL,NULL,NULL,true,true,16,'half',json_build_array(json_build_object('language','ru-RU','translation','Обновлено')),NULL,false,true);

DELETE FROM directus_relations
WHERE many_collection = 'tz_constructor_specs';

INSERT INTO directus_relations (many_collection, many_field, one_collection, one_field, one_allowed_collections, junction_field, sort_field, one_deselect_action)
VALUES
  ('tz_constructor_specs','category','product_categories',NULL,NULL,NULL,NULL,'nullify'),
  ('tz_constructor_specs','subcategory','product_subcategories',NULL,NULL,NULL,NULL,'nullify'),
  ('tz_constructor_specs','application_method','product_application_methods',NULL,NULL,NULL,NULL,'nullify');

DELETE FROM directus_permissions
WHERE collection = 'tz_constructor_specs';

INSERT INTO directus_permissions (collection, action, permissions, validation, presets, fields, policy)
SELECT 'tz_constructor_specs', action, '{}'::json, NULL, NULL, fields, policy::uuid
FROM (
  VALUES
    ('read', '*', '00000000-0000-4000-8000-000000000201'),
    ('read', '*', '00000000-0000-4000-8000-000000000202'),
    ('read', '*', '00000000-0000-4000-8000-000000000203'),
    ('read', '*', '00000000-0000-4000-8000-000000000204'),
    ('read', '*', '00000000-0000-4000-8000-000000000205'),
    ('read', '*', '00000000-0000-4000-8000-000000000206'),
    ('create', '*', '00000000-0000-4000-8000-000000000205'),
    ('update', '*', '00000000-0000-4000-8000-000000000205'),
    ('delete', '*', '00000000-0000-4000-8000-000000000205')
) AS p(action, fields, policy);

UPDATE contractors
SET can_mount = true
WHERE name ILIKE '%монтаж%';

SELECT
  (SELECT count(*) FROM tz_constructor_specs) AS tz_constructor_specs,
  (SELECT count(*) FROM product_categories WHERE name IN ('Постеры', 'Изделия из акрила и фанеры')) AS new_categories,
  (SELECT count(*) FROM product_subcategories WHERE name IN ('Открытки', 'Бейджи', 'Закладки', 'Паук', 'Брелки', 'Значки', 'Магниты', 'Стелы')) AS new_subcategories;
