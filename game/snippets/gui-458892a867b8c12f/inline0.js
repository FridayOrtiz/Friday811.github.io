
export async function psk_create(optionsJson) {
    const opts = JSON.parse(optionsJson);
    const publicKey = PublicKeyCredential.parseCreationOptionsFromJSON(opts.publicKey);
    const cred = await navigator.credentials.create({ publicKey });
    return JSON.stringify(cred.toJSON());
}
export async function psk_get(optionsJson) {
    const opts = JSON.parse(optionsJson);
    const publicKey = PublicKeyCredential.parseRequestOptionsFromJSON(opts.publicKey);
    const cred = await navigator.credentials.get({ publicKey });
    return JSON.stringify(cred.toJSON());
}
