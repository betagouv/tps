import { fire } from '@utils';

export default class AutosaveController {
  constructor() {
    this.latestPromise = Promise.resolve();
  }

  // Add a new autosave request to the queue.
  // It will be started after the previous one finishes (to prevent older form data
  // to overwrite newer data if the server does not repond in order.)
  enqueueAutosaveRequest(form) {
    this.latestPromise = this.latestPromise.finally(() => {
      return this._sendAutosaveRequest(form)
        .then(this._didSucceed)
        .catch(this._didFail);
    });
    this._didEnqueue();
  }

  // Create a fetch request that saves the form.
  // Returns a promise fulfilled when the request completes.
  _sendAutosaveRequest(form) {
    const autosavePromise = new Promise((resolve, reject) => {
      if (!document.body.contains(form)) {
        return reject(new Error('The form can no longer be found.'));
      }

      const [formData, formDataError] = this._formDataForDraft(form);
      if (formDataError) {
        formDataError.message = `Error while generating the form data (${formDataError.message})`;
        return reject(formDataError);
      }

      const fetchOptions = {
        method: form.method,
        body: formData,
        headers: { Accept: 'application/json' }
      };

      return window.fetch(form.action, fetchOptions).then(response => {
        if (response.ok) {
          resolve(response);
        } else {
          const message = `Network request failed (${response.status}, "${response.statusText}")`;
          reject(new Error(message));
        }
      });
    });

    return autosavePromise;
  }

  // Extract a FormData object of the form fields.
  _formDataForDraft(form) {
    // File inputs are handled separatly by ActiveStorage:
    // exclude them from the draft (by disabling them).
    // (Also Safari has issue with FormData containing empty file inputs)
    const fileInputs = form.querySelectorAll(
      'input[type="file"]:not([disabled])'
    );
    fileInputs.forEach(fileInput => (fileInput.disabled = true));

    // Generate the form data
    let formData = null;
    try {
      formData = new FormData(form);
      return [formData, null];
    } catch (error) {
      return [null, error];
    } finally {
      // Re-enable disabled file inputs
      fileInputs.forEach(fileInput => (fileInput.disabled = false));
    }
  }

  _didEnqueue() {
    fire(document, 'autosave:enqueue');
  }

  _didSucceed(response) {
    fire(document, 'autosave:end', response);
  }

  _didFail(error) {
    fire(document, 'autosave:error', error);
  }
}
