import { createSymbolikaSectionModule } from '../symbolika-costing-module/index.js';

export default {
  id: 'symbolika-contractor',
  name: 'Кабинет',
  icon: 'assignment_ind',
  color: '#F97316',
  routes: [
    {
      path: '',
      component: createSymbolikaSectionModule('contractor'),
    },
  ],
};
