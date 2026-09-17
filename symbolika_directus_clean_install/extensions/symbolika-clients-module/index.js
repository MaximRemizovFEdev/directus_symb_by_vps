import { createSymbolikaSectionModule } from '../symbolika-costing-module/index.js';

export default {
  id: 'symbolika-clients',
  name: 'Клиенты',
  icon: 'groups',
  color: '#F97316',
  routes: [
    {
      path: '',
      component: createSymbolikaSectionModule('clients'),
    },
  ],
};
