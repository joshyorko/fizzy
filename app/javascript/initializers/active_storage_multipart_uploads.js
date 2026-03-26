import { DirectUpload } from "@rails/activestorage"
import { createFileChecksum } from "lib/active_storage/file_checksum"

const originalCreate = DirectUpload.prototype.create
const multipartThreshold = Number.parseInt(
  document.head.querySelector('meta[name="active-storage-multipart-threshold"]')?.content || "",
  10
)

if (!DirectUpload.prototype.multipartUploadsPatched) {
  DirectUpload.prototype.multipartUploadsPatched = true

  DirectUpload.prototype.create = function(callback) {
    if (!shouldUseMultipart(this.file)) {
      return originalCreate.call(this, callback)
    }

    const multipartUpload = new MultipartDirectUpload(this)
    multipartUpload.create(callback)
  }
}

class MultipartDirectUpload {
  constructor(directUpload) {
    this.directUpload = directUpload
    this.file = directUpload.file
    this.url = directUpload.url.replace(/\/direct_uploads$/, "/multipart_uploads")
    this.delegate = directUpload.delegate
  }

  async create(callback) {
    let multipartData

    try {
      const checksum = await createFileChecksum(this.file)
      const response = await this.createBlob(checksum)
      const { multipart_upload, ...blob } = response

      multipartData = multipart_upload

      await this.uploadParts(multipart_upload)
      const completedBlob = await this.complete(multipart_upload)

      callback(null, completedBlob || blob)
    } catch (error) {
      if (multipartData) this.abort(multipartData)
      callback(error)
    }
  }

  async createBlob(checksum) {
    const xhr = new XMLHttpRequest()
    xhr.open("POST", this.url, true)
    xhr.responseType = "json"
    xhr.setRequestHeader("Content-Type", "application/json")
    xhr.setRequestHeader("Accept", "application/json")
    xhr.setRequestHeader("X-Requested-With", "XMLHttpRequest")

    const csrfToken = document.head.querySelector('meta[name="csrf-token"]')?.content
    if (csrfToken) xhr.setRequestHeader("X-CSRF-Token", csrfToken)

    notify(this.delegate, "directUploadWillCreateBlobWithXHR", xhr)

    return new Promise((resolve, reject) => {
      xhr.addEventListener("load", () => {
        if (xhr.status >= 200 && xhr.status < 300) {
          resolve(xhr.response)
        } else {
          reject(`Error creating Blob for "${this.file.name}". Status: ${xhr.status}`)
        }
      })

      xhr.addEventListener("error", () => {
        reject(`Error creating Blob for "${this.file.name}". Status: ${xhr.status}`)
      })

      xhr.send(JSON.stringify({
        blob: {
          filename: this.file.name,
          content_type: this.file.type || "application/octet-stream",
          byte_size: this.file.size,
          checksum: checksum
        }
      }))
    })
  }

  async uploadParts(multipartUpload) {
    const progressTracker = createProgressTracker(this.delegate, this.file.size)
    let uploadedBytes = 0

    for (const part of multipartUpload.parts) {
      const start = (part.part_number - 1) * multipartUpload.part_size
      const end = Math.min(start + multipartUpload.part_size, this.file.size)
      const chunk = this.file.slice(start, end)

      part.etag = await uploadPart(part.url, chunk, uploadedBytes, this.file.size, progressTracker)
      uploadedBytes += chunk.size
      progressTracker.dispatch(uploadedBytes)
    }
  }

  async complete(multipartUpload) {
    const response = await fetch(multipartUpload.complete_url, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Accept": "application/json",
        "X-CSRF-Token": document.head.querySelector('meta[name="csrf-token"]')?.content
      },
      body: JSON.stringify({
        multipart_upload: {
          upload_id: multipartUpload.upload_id,
          parts: multipartUpload.parts.map(part => ({
            part_number: part.part_number,
            etag: part.etag
          }))
        }
      })
    })

    if (!response.ok) {
      throw `Error storing "${this.file.name}". Status: ${response.status}`
    }

    return await response.json()
  }

  async abort(multipartUpload) {
    try {
      await fetch(`${multipartUpload.abort_url}?upload_id=${encodeURIComponent(multipartUpload.upload_id)}`, {
        method: "DELETE",
        headers: {
          "X-CSRF-Token": document.head.querySelector('meta[name="csrf-token"]')?.content
        }
      })
    } catch (_error) {
    }
  }
}

function shouldUseMultipart(file) {
  return Number.isFinite(multipartThreshold) && file.size >= multipartThreshold
}

function createProgressTracker(delegate, totalBytes) {
  const request = {
    upload: new EventTarget(),
    withCredentials: false
  }

  notify(delegate, "directUploadWillStoreFileWithXHR", request)

  return {
    dispatch(loadedBytes) {
      request.upload.dispatchEvent(new ProgressEvent("progress", {
        lengthComputable: true,
        loaded: loadedBytes,
        total: totalBytes
      }))
    }
  }
}

function uploadPart(url, chunk, uploadedBytes, totalBytes, progressTracker) {
  return new Promise((resolve, reject) => {
    const xhr = new XMLHttpRequest()
    xhr.open("PUT", url, true)
    xhr.responseType = "text"

    xhr.upload.addEventListener("progress", event => {
      if (!event.lengthComputable) return

      progressTracker.dispatch(uploadedBytes + event.loaded)
    })

    xhr.addEventListener("load", () => {
      if (xhr.status >= 200 && xhr.status < 300) {
        progressTracker.dispatch(Math.min(uploadedBytes + chunk.size, totalBytes))
        resolve(xhr.getResponseHeader("ETag"))
      } else {
        reject(`Error storing "${chunk.name || "file"}". Status: ${xhr.status}`)
      }
    })

    xhr.addEventListener("error", () => {
      reject(`Error storing "${chunk.name || "file"}". Status: ${xhr.status}`)
    })

    xhr.send(chunk)
  })
}

function notify(object, methodName, ...messages) {
  if (object && typeof object[methodName] == "function") {
    return object[methodName](...messages)
  }
}
