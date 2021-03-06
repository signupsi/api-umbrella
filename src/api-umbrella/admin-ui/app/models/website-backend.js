import Model, { attr } from '@ember-data/model';
import { buildValidations, validator } from 'ember-cp-validations';

import I18n from 'i18n-js';

const Validations = buildValidations({
  frontendHost: [
    validator('presence', true),
    validator('format', {
      regex: CommonValidations.host_format_with_wildcard,
      message: I18n.t('errors.messages.invalid_host_format'),
    }),
  ],
  backendProtocol: validator('presence', true),
  serverHost: [
    validator('presence', true),
    validator('format', {
      regex: CommonValidations.host_format_with_wildcard,
      message: I18n.t('errors.messages.invalid_host_format'),
    }),
  ],
  serverPort: [
    validator('presence', true),
    validator('number', { allowString: true }),
  ],
});

export default Model.extend(Validations, {
  frontendHost: attr(),
  backendProtocol: attr('string', { defaultValue: 'http' }),
  serverHost: attr(),
  serverPort: attr('number', { defaultValue: 80 }),
  createdAt: attr(),
  updatedAt: attr(),
  creator: attr(),
  updater: attr(),
}).reopenClass({
  urlRoot: '/api-umbrella/v1/website_backends',
  singlePayloadKey: 'website_backend',
  arrayPayloadKey: 'data',
});
