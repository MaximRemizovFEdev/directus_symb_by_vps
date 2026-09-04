import { createSymbolikaSectionModule } from '../symbolika-costing-module/index.js';

export default {
  id: 'symbolika-admin',
  name: 'Админка',
  icon: 'admin_panel_settings',
  color: '#F97316',
  routes: [
    {
      path: '',
      component: createSymbolikaSectionModule('admin'),
    },
  ],
};
