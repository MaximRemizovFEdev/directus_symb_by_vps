import { createSymbolikaSectionModule } from '../symbolika-costing-module/index.js';

export default {
  id: 'symbolika-tasks',
  name: 'Задачи',
  icon: 'checklist',
  color: '#F97316',
  routes: [
    {
      path: '',
      component: createSymbolikaSectionModule('tasks'),
    },
  ],
};
