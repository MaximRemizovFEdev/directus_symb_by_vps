export default {
  id: 'symbolika-order-link',
  name: 'Symbolika: order link',
  icon: 'open_in_new',
  description: 'Button link from read-only order views to the editable source order.',
  component: {
    props: {
      value: {
        type: [String, Number],
        default: null,
      },
      disabled: {
        type: Boolean,
        default: false,
      },
    },

    data() {
      return {
        isHovering: false,
        accessChecked: false,
        hasAccess: false,
      };
    },

    computed: {
      orderId() {
        if (this.value && typeof this.value === 'object') return this.value.id;
        return this.value;
      },

      canOpen() {
        return this.hasAccess && this.orderId !== null && this.orderId !== undefined && this.orderId !== '';
      },

      buttonStyle() {
        const base = {
          inlineSize: 'min(100%, 240px)',
          blockSize: 'var(--theme--form--field--input--height)',
          display: 'inline-flex',
          alignItems: 'center',
          justifyContent: 'center',
          gap: '8px',
          border: '0',
          borderRadius: 'var(--theme--border-radius)',
          color: '#111827',
          background: 'var(--theme--primary)',
          font: 'inherit',
          fontSize: '15px',
          fontWeight: '700',
          cursor: this.canOpen ? 'pointer' : 'not-allowed',
          padding: '0 18px',
          boxShadow: 'none',
          opacity: this.canOpen ? '1' : '.72',
          transition: 'background-color 120ms ease, box-shadow 120ms ease',
        };

        if (!this.canOpen) {
          return {
            ...base,
            color: 'var(--theme--foreground-subdued)',
            background: 'var(--theme--form--field--input--background-subdued)',
          };
        }

        if (this.isHovering) {
          return {
            ...base,
            background: 'color-mix(in srgb, var(--theme--primary) 88%, white)',
            boxShadow: '0 0 0 1px color-mix(in srgb, var(--theme--primary) 70%, white) inset, 0 8px 18px rgb(0 0 0 / 18%)',
          };
        }

        return base;
      },
    },

    watch: {
      orderId: {
        immediate: true,
        handler() {
          this.checkAccess();
        },
      },
    },

    methods: {
      async checkAccess() {
        this.accessChecked = false;
        this.hasAccess = false;

        if (this.orderId === null || this.orderId === undefined || this.orderId === '') {
          this.accessChecked = true;
          return;
        }

        try {
          const response = await fetch(`/items/orders/${this.orderId}?fields=id`, {
            credentials: 'same-origin',
          });

          this.hasAccess = response.ok;
        } catch {
          this.hasAccess = false;
        } finally {
          this.accessChecked = true;
        }
      },

      openOrder() {
        if (!this.canOpen) return;
        window.location.assign(`/admin/content/orders/${this.orderId}`);
      },
    },

    template: `
      <button
        v-if="accessChecked && hasAccess"
        type="button"
        class="symbolika-order-link"
        :style="buttonStyle"
        :class="{ 'is-disabled': !canOpen }"
        :disabled="!canOpen"
        @mouseenter="isHovering = true"
        @mouseleave="isHovering = false"
        @click="openOrder"
      >
        <span class="symbolika-order-link__icon" style="color: #111827; font-size: 18px; line-height: 1;">↗</span>
        <span>Открыть заказ</span>
      </button>
    `,
  },
  types: ['integer', 'bigInteger', 'uuid', 'string'],
  localTypes: ['standard'],
  group: 'presentation',
  options: null,
};
