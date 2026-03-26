import SparkMD5 from "spark-md5"

const fileSlice = Blob.prototype.slice || Blob.prototype.mozSlice || Blob.prototype.webkitSlice

export function createFileChecksum(file, { chunkSize = 2097152, format = "base64" } = {}) {
  return new Promise((resolve, reject) => {
    const buffer = new SparkMD5.ArrayBuffer()
    const chunkCount = Math.ceil(file.size / chunkSize)
    let chunkIndex = 0

    const fileReader = new FileReader()

    fileReader.addEventListener("load", event => {
      buffer.append(event.target.result)

      if (readNextChunk()) return

      resolve(format == "hex" ? buffer.end() : btoa(buffer.end(true)))
    })

    fileReader.addEventListener("error", () => {
      reject(`Error reading ${file.name || "file"}`)
    })

    function readNextChunk() {
      if (chunkIndex < chunkCount || (chunkIndex === 0 && chunkCount === 0)) {
        const start = chunkIndex * chunkSize
        const end = Math.min(start + chunkSize, file.size)
        fileReader.readAsArrayBuffer(fileSlice.call(file, start, end))
        chunkIndex += 1
        return true
      } else {
        return false
      }
    }

    readNextChunk()
  })
}
