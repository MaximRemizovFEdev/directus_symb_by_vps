import { createSymbolikaSectionModule } from '../symbolika-costing-module/index.js';

export default {
  id: 'symbolika-finance',
  name: 'Финансы',
  icon: 'receipt_long',
  color: '#F97316',
  routes: [
    {
      path: '',
      component: createSymbolikaSectionModule('finance'),
    },
  ],
};
