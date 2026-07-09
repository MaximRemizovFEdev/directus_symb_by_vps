export default {
  id: 'symbolika-live-calc',
  name: 'Символика: живой расчет позиции',
  icon: 'calculate',
  description: 'Показывает предварительный расчет позиции заказа до сохранения.',
  component: {
    props: {
      value: {
        type: [String, Number, Object, Array, Boolean],
        default: null,
      },
      values: {
        type: Object,
        default: () => ({}),
      },
      disabled: {
        type: Boolean,
        default: false,
      },
    },

    computed: {
      quantity() {
        return this.toNumber(this.values.quantity);
      },

      pricePerUnit() {
        return this.toNumber(this.values.price_per_unit);
      },

      contractor1Cost() {
        return this.toNumber(this.values.contractor_1_cost);
      },

      contractor2Cost() {
        return this.toNumber(this.values.contractor_2_cost);
      },

      managerPercent() {
        return this.toNumber(this.values.manager_percent);
      },

      taxPercent() {
        return this.toNumber(this.values.tax_percent);
      },

      unitCost() {
        return this.round(this.contractor1Cost + this.contractor2Cost);
      },

      totalCost() {
        return this.round(this.unitCost * this.quantity);
      },

      orderSum() {
        return this.round(this.quantity * this.pricePerUnit);
      },

      managerCommissionSum() {
        return this.round(this.orderSum * this.managerPercent / 100);
      },

      taxSum() {
        return this.round(this.orderSum * this.taxPercent / 100);
      },

      profitSum() {
        return this.round(this.orderSum - this.totalCost - this.managerCommissionSum - this.taxSum);
      },

      marginPercent() {
        if (this.orderSum <= 0) return 0;
        return this.round(this.profitSum / this.orderSum * 100);
      },
    },

    methods: {
      toNumber(value) {
        const normalized = String(value ?? '')
          .replace(/\s/g, '')
          .replace(',', '.');

        const number = Number(normalized);
        return Number.isFinite(number) ? number : 0;
      },

      round(value) {
        return Math.round(this.toNumber(value) * 100) / 100;
      },

      money(value) {
        return new Intl.NumberFormat('ru-RU', {
          minimumFractionDigits: 2,
          maximumFractionDigits: 2,
        }).format(this.toNumber(value)) + ' ₽';
      },

      percent(value) {
        return new Intl.NumberFormat('ru-RU', {
          minimumFractionDigits: 2,
          maximumFractionDigits: 2,
        }).format(this.toNumber(value)) + ' %';
      },
    },

    template: `
      <div class="symbolika-live-calc">
        <div class="symbolika-live-calc__title">
          Предварительный расчет
        </div>

        <div class="symbolika-live-calc__grid">
          <div class="symbolika-live-calc__item">
            <div class="symbolika-live-calc__label">Сумма позиции</div>
            <div class="symbolika-live-calc__value">{{ money(orderSum) }}</div>
          </div>

          <div class="symbolika-live-calc__item">
            <div class="symbolika-live-calc__label">Себестоимость за единицу</div>
            <div class="symbolika-live-calc__value">{{ money(unitCost) }}</div>
          </div>

          <div class="symbolika-live-calc__item">
            <div class="symbolika-live-calc__label">Себестоимость всего</div>
            <div class="symbolika-live-calc__value">{{ money(totalCost) }}</div>
          </div>

          <div class="symbolika-live-calc__item">
            <div class="symbolika-live-calc__label">Комиссия менеджера</div>
            <div class="symbolika-live-calc__value">{{ money(managerCommissionSum) }}</div>
          </div>

          <div class="symbolika-live-calc__item">
            <div class="symbolika-live-calc__label">Налог</div>
            <div class="symbolika-live-calc__value">{{ money(taxSum) }}</div>
          </div>

          <div class="symbolika-live-calc__item symbolika-live-calc__item--profit">
            <div class="symbolika-live-calc__label">Прибыль</div>
            <div class="symbolika-live-calc__value">{{ money(profitSum) }}</div>
          </div>

          <div class="symbolika-live-calc__item symbolika-live-calc__item--margin">
            <div class="symbolika-live-calc__label">Маржинальность</div>
            <div class="symbolika-live-calc__value">{{ percent(marginPercent) }}</div>
          </div>
        </div>

        <div class="symbolika-live-calc__note">
          Это предварительный расчет до сохранения. После сохранения итоговые поля пересчитает hook.
        </div>
      </div>
    `,
  },
  types: ['alias', 'string', 'text'],
  localTypes: ['presentation'],
  group: 'presentation',
  options: null,
  recommendedDisplays: [],
};
