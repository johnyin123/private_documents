/* FOR DEMO */
const dialog = new Dialog();

/* alert */
document.getElementById('btnAlert').addEventListener('click', (e) => {
  dialog.alert('Please refresh your browser!').then((res) => {  console.log(res) })
});

/* confirm */
document.getElementById('btnConfirm').addEventListener('click', () => {
  dialog.confirm('Do you want to continue?').then((res) => {  console.log(res) })
});

/* prompt */
document.getElementById('btnPrompt').addEventListener('click', (e) => {
  dialog.prompt('The meaning of life?', 42).then((res) => {  console.log(res) })
});

/* custom */
document.getElementById('btnCustom').addEventListener('click', (e) => {
  dialog.open({
    accept: 'Sign in',
    dialogClass: 'custom',
    message: 'Please enter your credentials',
    soundAccept: 'https://assets.stoumann.dk/audio/accept.mp3',
    soundOpen: 'https://assets.stoumann.dk/audio/open.mp3',
    target: e.target,
    template: `
    <label>Username<input type="text" name="username" value="admin"></label>
    <label>Password<input type="password" name="password" value="password"></label>`
  })
  dialog.waitForUser().then((res) => {  console.log(res) })
});
