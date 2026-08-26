import assert from 'node:assert/strict';
import test from 'node:test';

import { CostingModule } from '../index.js';

function routingContext({ override = false } = {}) {
  return {
    ...CostingModule.methods,
    itemNeedsBlank: () => true,
    hasManagerOverrideAccess: override,
    productCategories: [{ id: 10, name: 'Textile' }],
    contractors: [
      { id: 1, name: 'Configured', approval_status: 'approved' },
      { id: 2, name: 'Manual override', approval_status: 'approved' },
      { id: 3, name: 'Pending', approval_status: 'pending' },
    ],
    contractorCapabilities: [
      {
        id: 100,
        capability_type: 'executor',
        product_category: 10,
        product_subcategory: null,
        application_method: null,
        contractor: 1,
        is_active: true,
      },
    ],
  };
}

test('routing limits ordinary users to configured contractors', () => {
  const context = routingContext();
  const options = context.capabilityContractorOptions(
    { product_category: 10, blank_source: 'none' },
    'executor',
  );

  assert.deepEqual(options.map((contractor) => contractor.id), [1]);
});

test('administrator and managing may override a configured contractor', () => {
  const context = routingContext({ override: true });
  const options = context.capabilityContractorOptions(
    { product_category: 10, blank_source: 'none' },
    'executor',
  );

  assert.deepEqual(options.map((contractor) => contractor.id), [1, 2]);
});

test('blank supplier and executor use separate contractor slots', () => {
  const context = routingContext({ override: true });
  const item = {
    product_category: 10,
    blank_source: 'supplier',
    contractor_1: 1,
    contractor_2: 2,
  };

  assert.equal(context.executorField(item), 'contractor_2');
  assert.equal(context.executorCostField(item), 'contractor_2_cost');
});

test('customer blank and full-service contractor keep executor cost in the work slot', () => {
  const context = routingContext({ override: true });

  for (const blankSource of ['customer', 'warehouse', 'contractor']) {
    const item = {
      product_category: 10,
      blank_source: blankSource,
      contractor_1: null,
      contractor_2: 2,
      contractor_2_cost: 315,
    };

    assert.equal(context.executorField(item), 'contractor_2');
    assert.equal(context.executorCostField(item), 'contractor_2_cost');
  }
});

test('changing to a customer blank or full-service contractor only clears blank supplier data', () => {
  const context = routingContext({ override: true });

  for (const blankSource of ['customer', 'warehouse', 'contractor']) {
    const item = {
      product_category: 10,
      blank_source: blankSource,
      contractor_1: 1,
      contractor_1_cost: 100,
      contractor_2: 2,
      contractor_2_cost: 315,
    };

    context.handleBlankSourceChange(item);

    assert.equal(item.contractor_1, '');
    assert.equal(item.contractor_1_cost, '');
    assert.equal(item.contractor_2, 2);
    assert.equal(item.contractor_2_cost, 315);
  }
});

test('full-service contractor uses a combined finished-product cost label', () => {
  const context = routingContext({ override: true });

  assert.equal(
    context.executorCostLabel({ blank_source: 'contractor' }),
    'Себестоимость готового изделия за ед.',
  );
  assert.equal(
    context.executorCostLabel({ blank_source: 'customer' }),
    'Себестоимость работ за ед.',
  );
});
