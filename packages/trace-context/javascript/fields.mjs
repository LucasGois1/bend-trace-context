// The fields of a message as the facade takes them: an array of
// [name, value] string pairs in the message's order. The fields are copied
// in one pass, each read once, so that what was checked is what is used,
// even when the array or its pairs have getters or are proxies.
export function copyFields(fields) {
  if (!Array.isArray(fields)) throw new TypeError('fields must be an array of [name, value] string pairs');
  const length = fields.length;
  const copy = [];
  for (let index = 0; index < length; index += 1) {
    const field = fields[index];
    if (!Array.isArray(field) || field.length !== 2) {
      throw new TypeError(`fields[${index}] must be a [name, value] pair of strings`);
    }
    const name = field[0];
    const value = field[1];
    if (typeof name !== 'string' || typeof value !== 'string') {
      throw new TypeError(`fields[${index}] must be a [name, value] pair of strings`);
    }
    copy.push([name, value]);
  }
  return copy;
}
