import { createSymbolikaSectionModule } from '../symbolika-costing-module/index.js';

export default {
  id: 'symbolika-management',
  name: 'Управление',
  icon: 'dashboard_customize',
  color: '#F97316',
  routes: [
    {
      path: '',
      component: createSymbolikaSectionModule('management'),
    },
  ],
};
