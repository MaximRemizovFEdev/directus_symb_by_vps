import { createSymbolikaSectionModule } from '../symbolika-costing-module/index.js';

export default {
  id: 'symbolika-production',
  name: 'Производство',
  icon: 'precision_manufacturing',
  color: '#F97316',
  routes: [
    {
      path: '',
      component: createSymbolikaSectionModule('production'),
    },
  ],
};
