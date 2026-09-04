import { createSymbolikaSectionModule } from '../symbolika-costing-module/index.js';

export default {
  id: 'symbolika-notifications',
  name: 'Центр уведомлений',
  icon: 'notifications',
  color: '#F97316',
  routes: [
    {
      path: '',
      component: createSymbolikaSectionModule('notifications'),
    },
  ],
};
