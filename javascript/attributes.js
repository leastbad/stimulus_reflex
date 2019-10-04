import { dasherize, underscore } from 'inflected'

// Returns a string value for the passed array.
//
//   attributeValue(['', 'one', null, 'two', 'three ']) // 'one two three'
//
export const attributeValue = (values = []) => {
  const value = values
    .filter(v => v && String(v).length)
    .map(v => v.trim())
    .join(' ')
    .trim()
  return value.length ? value : null
}

// Returns an array for the passed string value by splitting on whitespace.
//
//   attributeValues('one two three ') // ['one', 'two', 'three']
//
export const attributeValues = value => {
  if (!value) return []
  if (!value.length) return []
  return value.split(' ').filter(v => v.trim().length)
}

// Extracts attributes from a DOM element.
//
export const extractElementAttributes = element => {
  let attrs = Array.prototype.slice
    .call(element.attributes)
    .reduce((memo, attr) => {
      memo[attr.name] = attr.value
      return memo
    }, {})

  attrs.value = element.value
  attrs.checked = !!element.checked
  attrs.selected = !!element.selected
  if (element.tagName.match(/select/i)) {
    if (element.multiple) {
      const checkedOptions = Array.prototype.slice.call(
        element.querySelectorAll('option:checked')
      )
      attrs.values = checkedOptions.map(o => o.value)
    } else if (element.selectedIndex > -1) {
      attrs.value = element.options[element.selectedIndex].value
    }
  }
  return attrs
}

// Finds an element based on the passed represention the DOM element's attributes.
//
// NOTE: This is the same set of attributes extrated via extractElementAttributes and forwarded to the server side reflex.
// SEE: stimulute()
// SEE: StimulusReflex::Channel#broadcast_morph
// SEE: StimulusReflex::Channel#broadcast_error
//
export const findElement = attributes => {
  attributes = attributes || {}
  let elements = []
  if (attributes.id) {
    elements = document.querySelectorAll(`#${attributes.id}`)
  } else {
    let selectors = []
    for (const key in attributes) {
      if (key.includes('.')) continue
      if (key === 'value') continue
      if (key === 'checked') continue
      if (key === 'selected') continue
      if (!Object.prototype.hasOwnProperty.call(attributes, key)) continue
      selectors.push(`[${key}="${attributes[key]}"]`)
    }
    try {
      elements = document.querySelectorAll(selectors.join(''))
    } catch (error) {
      console.log(
        'StimulusReflex encountered an error identifying the Stimulus element. Consider adding an #id to the element.',
        error,
        attributes
      )
    }
  }

  const element = elements.length === 1 ? elements[0] : null
  return element
}

// Returns the expected matching controller name for the passed reflex.
//
//   matchingControllerName('ExampleReflex#do_stuff') // 'example'
//
const matchingControllerName = reflex => {
  return dasherize(underscore(reflex.split('#')[0].replace(/Reflex$/, '')))
}

// Finds the registered StimulusReflex controller for the passed element that matches the reflex.
// Traverses DOM ancestors starting with element until a match is found.
//
export const findReflexController = (application, element, reflex) => {
  const name = matchingControllerName(reflex)
  let controller
  while (element && !controller) {
    const controllers = attributeValues(element.dataset.controller)
    if (controllers.includes(name)) {
      const candidate = application.getControllerForElementAndIdentifier(
        element,
        name
      )
      if (candidate && candidate.StimulusReflex) controller = candidate
    }
    element = element.parentElement
  }
  return controller
}
