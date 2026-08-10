import { createSymbolikaSectionModule } from '../symbolika-costing-module/index.js';

export default {
  id: 'symbolika-profile-module',
  name: 'Личный кабинет',
  icon: 'account_circle',
  color: '#F97316',
  routes: [
    {
      path: '',
      component: createSymbolikaSectionModule('profile'),
    },
  ],
};
