import { createSymbolikaSectionModule } from '../symbolika-costing-module/index.js';

export default {
  id: 'symbolika-procurement',
  name: 'Закупки',
  icon: 'shopping_cart_checkout',
  color: '#F97316',
  routes: [
    {
      path: '',
      component: createSymbolikaSectionModule('procurement'),
    },
  ],
};
