# Symbolika Live Calc Interface

Кастомный интерфейс Directus для живого предварительного расчета позиции заказа.

## Что считает

В коллекции `orders_items` берет текущие значения формы:

- `quantity`
- `price_per_unit`
- `contractor_1_cost`
- `contractor_2_cost`
- `manager_percent`
- `tax_percent`

И показывает:

- сумму позиции
- себестоимость за единицу
- себестоимость всего
- комиссию менеджера
- налог
- прибыль
- маржинальность

## Важно

Интерфейс ничего не записывает в базу.  
Он только показывает предварительный расчет до сохранения.

Итоговые значения после сохранения продолжает считать основной hook `symbolika-calculations`.

## Установка

1. Распаковать архив на сервере:

```bash
cd /root
unzip symbolika-live-calc-interface.zip
```

2. Скопировать расширение в папку проекта:

```bash
cp -r /root/symbolika-live-calc-interface /root/symbolika_directus_clean_install/extensions/
```

3. Скопировать в контейнер:

```bash
docker cp /root/symbolika_directus_clean_install/extensions/symbolika-live-calc-interface symbolika-directus:/directus/extensions/
```

4. Перезапустить Directus:

```bash
docker restart symbolika-directus
```

5. Проверить логи:

```bash
docker logs --tail=60 symbolika-directus
```

## Настройка в Directus

1. Открыть:

`Настройки → Модель данных → orders_items`

2. Создать новое поле:

- Field: `live_calc_preview`
- Type: `Alias`
- Interface: `Символика: живой расчет позиции`
- Русское название: `Предварительный расчет`

3. Перетащить поле ниже финансовых полей позиции.

## Если интерфейс не появился

Проверь, что папка лежит так:

```text
/directus/extensions/symbolika-live-calc-interface/index.js
/directus/extensions/symbolika-live-calc-interface/package.json
```

Потом перезапусти контейнер.
