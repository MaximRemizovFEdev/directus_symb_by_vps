export default {
  id: 'symbolika-autosave-select',
  name: 'Symbolika: autosave select',
  icon: 'save',
  description: 'Select dropdown that saves the current field immediately after a value change.',
  component: {
    props: {
      value: {
        type: [String, Number, Boolean],
        default: null,
      },
      collection: {
        type: String,
        default: null,
      },
      field: {
        type: String,
        default: null,
      },
      primaryKey: {
        type: [String, Number],
        default: null,
      },
      options: {
        type: Object,
        default: () => ({}),
      },
      choices: {
        type: Array,
        default: () => [],
      },
      disabled: {
        type: Boolean,
        default: false,
      },
    },

    emits: ['input'],

    data() {
      return {
        localValue: this.value ?? '',
        state: 'idle',
      };
    },

    computed: {
      normalizedChoices() {
        if (Array.isArray(this.choices) && this.choices.length > 0) return this.choices;
        return Array.isArray(this.options?.choices) ? this.options.choices : [];
      },

      canAutosave() {
        return Boolean(this.collection && this.field && this.primaryKey && this.primaryKey !== '+');
      },

      shouldLeaveCurrentViewAfterSave() {
        return this.collection === 'office_items_in_office'
          && this.field === 'office_status'
          && this.localValue !== 'in_office';
      },

      shouldRefreshParentAfterSave() {
        return this.collection === 'office_issue_items' && this.field === 'office_status';
      },

      stateLabel() {
        if (this.state === 'saving') return '...';
        if (this.state === 'saved') return String.fromCharCode(10003);
        if (this.state === 'error') return '!';
        return '';
      },

      controlStyle() {
        return {
          appearance: 'none',
          WebkitAppearance: 'none',
          inlineSize: '100%',
          blockSize: 'var(--theme--form--field--input--height)',
          border: 'var(--theme--border-width) solid var(--theme--form--field--input--border-color)',
          borderRadius: 'var(--theme--border-radius)',
          color: this.disabled ? 'var(--theme--foreground-subdued)' : 'var(--theme--foreground)',
          background: this.disabled
            ? 'var(--theme--form--field--input--background-subdued)'
            : 'var(--theme--form--field--input--background)',
          font: 'inherit',
          padding: '0 72px 0 16px',
          outline: 'none',
          cursor: this.disabled ? 'not-allowed' : 'pointer',
          boxSizing: 'border-box',
        };
      },

      chevronStyle() {
        return {
          position: 'absolute',
          insetBlockStart: '50%',
          insetInlineEnd: '16px',
          inlineSize: '10px',
          blockSize: '10px',
          borderInlineEnd: '2px solid var(--theme--foreground-subdued)',
          borderBlockEnd: '2px solid var(--theme--foreground-subdued)',
          transform: 'translateY(-65%) rotate(45deg)',
          pointerEvents: 'none',
        };
      },

      stateStyle() {
        return {
          position: 'absolute',
          insetBlockStart: '50%',
          insetInlineEnd: '48px',
          transform: 'translateY(-50%)',
          color: this.state === 'error' ? 'var(--theme--danger)' : 'var(--theme--primary)',
          fontWeight: '700',
          lineHeight: '1',
          pointerEvents: 'none',
        };
      },

      wrapperStyle() {
        return {
          position: 'relative',
          inlineSize: '100%',
        };
      },
    },

    watch: {
      value(next) {
        this.localValue = next ?? '';
      },
    },

    methods: {
      async onChange(event) {
        const next = event.target.value;
        this.localValue = next;

        if (!this.canAutosave) {
          this.$emit('input', next);
          return;
        }

        this.state = 'saving';

        try {
          const payload = { [this.field]: next };

          if (this.$api?.patch) {
            await this.$api.patch(`/items/${this.collection}/${this.primaryKey}`, payload);
          } else {
            const response = await fetch(`/items/${this.collection}/${this.primaryKey}`, {
              method: 'PATCH',
              credentials: 'include',
              headers: { 'Content-Type': 'application/json' },
              body: JSON.stringify(payload),
            });

            if (!response.ok) throw new Error(`Autosave failed: ${response.status}`);
          }

          this.state = 'saved';
          this.$emit('input', next);

          if (this.shouldLeaveCurrentViewAfterSave) {
            window.setTimeout(() => {
              window.location.assign('/admin/content/office_items_in_office');
            }, 700);
            return;
          }

          if (this.shouldRefreshParentAfterSave) {
            window.setTimeout(() => {
              window.location.reload();
            }, 700);
            return;
          }

          window.setTimeout(() => {
            if (this.state === 'saved') this.state = 'idle';
          }, 1800);
        } catch (error) {
          console.warn('[Symbolika autosave select]', error);
          this.state = 'error';
        }
      },
    },

    template: `
      <div class="symbolika-autosave-select" :class="'is-' + state" :style="wrapperStyle">
        <select
          class="symbolika-autosave-select__control"
          :style="controlStyle"
          :value="localValue"
          :disabled="disabled"
          @change="onChange"
      >
          <option
            v-for="choice in normalizedChoices"
            :key="choice.value"
            :value="choice.value"
          >
            {{ choice.text }}
          </option>
        </select>
        <span class="symbolika-autosave-select__chevron" :style="chevronStyle" aria-hidden="true"></span>
        <span class="symbolika-autosave-select__state" :style="stateStyle" aria-live="polite">{{ stateLabel }}</span>
      </div>
    `,
  },
  types: ['string'],
  localTypes: ['standard'],
  group: 'selection',
  options: null,
  styles: `
    .symbolika-autosave-select {
      position: relative;
      inline-size: 100%;
    }

    .symbolika-autosave-select__control {
      appearance: none;
      -webkit-appearance: none;
      inline-size: 100%;
      block-size: var(--theme--form--field--input--height);
      border: var(--theme--border-width) solid var(--theme--form--field--input--border-color);
      border-radius: var(--theme--border-radius);
      color: var(--theme--foreground);
      background: var(--theme--form--field--input--background);
      font: inherit;
      padding: 0 72px 0 16px;
      outline: none;
      cursor: pointer;
    }

    .symbolika-autosave-select__control:focus {
      border-color: var(--theme--primary);
      box-shadow: 0 0 0 1px var(--theme--primary) inset;
    }

    .symbolika-autosave-select__control:disabled {
      color: var(--theme--foreground-subdued);
      background: var(--theme--form--field--input--background-subdued);
      cursor: not-allowed;
    }

    .symbolika-autosave-select__chevron {
      position: absolute;
      inset-block-start: 50%;
      inset-inline-end: 16px;
      inline-size: 10px;
      block-size: 10px;
      border-inline-end: 2px solid var(--theme--foreground-subdued);
      border-block-end: 2px solid var(--theme--foreground-subdued);
      transform: translateY(-65%) rotate(45deg);
      pointer-events: none;
    }

    .symbolika-autosave-select__state {
      position: absolute;
      inset-block-start: 50%;
      inset-inline-end: 48px;
      transform: translateY(-50%);
      color: var(--theme--primary);
      font-weight: 700;
      line-height: 1;
      pointer-events: none;
    }

    .symbolika-autosave-select.is-error .symbolika-autosave-select__control {
      border-color: var(--theme--danger);
    }

    .symbolika-autosave-select.is-error .symbolika-autosave-select__state {
      color: var(--theme--danger);
    }
  `,
};
