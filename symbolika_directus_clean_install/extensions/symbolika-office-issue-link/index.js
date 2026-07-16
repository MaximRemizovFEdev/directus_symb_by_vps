export default {
  id: 'symbolika-office-issue-link',
  name: 'Symbolika: office issue link',
  icon: 'open_in_new',
  description: 'Button link from an office item to the office issue order view.',
  component: {
    props: {
      value: {
        type: [String, Number, Object],
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

    data() {
      return {
        isHovering: false,
      };
    },

    computed: {
      issueId() {
        if (this.value && typeof this.value === 'object') return this.value.id;
        return this.value;
      },

      canOpen() {
        return this.issueId !== null && this.issueId !== undefined && this.issueId !== '';
      },

      buttonStyle() {
        const base = {
          inlineSize: 'min(100%, 260px)',
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
          transform: 'translateY(0)',
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

    methods: {
      openIssue() {
        if (!this.canOpen) return;
        window.location.assign(`/admin/content/office_issue/${this.issueId}`);
      },
    },

    template: `
      <button
        type="button"
        class="symbolika-office-issue-link"
        :style="buttonStyle"
        :class="{ 'is-disabled': !canOpen }"
        :disabled="!canOpen"
        @mouseenter="isHovering = true"
        @mouseleave="isHovering = false"
        @click="openIssue"
      >
        <span class="symbolika-office-issue-link__icon" style="color: #111827; font-size: 18px; line-height: 1;">\u2197</span>
        <span>\u041f\u0435\u0440\u0435\u0439\u0442\u0438 \u0432 \u0437\u0430\u043a\u0430\u0437</span>
      </button>
    `,
  },
  types: ['integer', 'bigInteger', 'uuid', 'string'],
  localTypes: ['m2o'],
  group: 'presentation',
  options: null,
  styles: `
    .symbolika-office-issue-link {
      inline-size: min(100%, 260px);
      block-size: var(--theme--form--field--input--height);
      display: inline-flex;
      align-items: center;
      justify-content: center;
      gap: 8px;
      border: 0;
      border-radius: var(--theme--border-radius);
      color: #111827;
      background: var(--theme--primary);
      font: inherit;
      font-size: 15px;
      font-weight: 700;
      cursor: pointer;
      padding: 0 18px;
      box-shadow: none;
      transition: background-color 120ms ease, color 120ms ease, box-shadow 120ms ease, transform 120ms ease;
    }

    .symbolika-office-issue-link:hover {
      background: color-mix(in srgb, var(--theme--primary) 88%, white);
      box-shadow: 0 0 0 1px color-mix(in srgb, var(--theme--primary) 70%, white) inset, 0 8px 18px rgb(0 0 0 / 18%);
    }

    .symbolika-office-issue-link.is-disabled {
      color: var(--theme--foreground-subdued);
      background: var(--theme--form--field--input--background-subdued);
      cursor: not-allowed;
      opacity: .72;
      box-shadow: none;
    }

    .symbolika-office-issue-link__icon {
      color: #111827;
      font-size: 18px;
      line-height: 1;
    }
  `,
};
