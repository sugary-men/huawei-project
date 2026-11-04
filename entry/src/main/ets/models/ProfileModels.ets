export interface StudentProfile {
  studentId: string
  name: string
  college: string
  className: string
  dorm: string
  phone: string
  email: string
  emergencyName: string
  emergencyPhone: string
  defaultReason: string
}

export interface SecureProfileResult {
  ok: boolean
  message: string
  profile?: StudentProfile
}

export interface EncryptedEnvelope {
  version: number
  nonce: string
  cipherText: string
}
