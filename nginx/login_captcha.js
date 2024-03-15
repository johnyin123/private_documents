var CaptchaVerifyUrl = 'http://192.168.169.234:5000/api/verify';
dialog = new Dialog();
function captcha_check(res, real_login) {
  if (res == false){ return; }
  var sendObject = JSON.stringify(res);
  sendObject['timezone']=Intl.DateTimeFormat().resolvedOptions().timeZone;
  //sendObject['timezone']=(new Date()).getTimezoneOffset()/60;
  sendObject['epoch']=~~(Date.now()/1000);
  sendObject['language']=navigator.language;
  sendObject['platform']=navigator.platform;
  xhr=new XMLHttpRequest();
  xhr.open('POST', CaptchaVerifyUrl, true);
  xhr.onreadystatechange = function() {
    if(xhr.readyState !== 4) { return; }
    if(xhr.status === 200) {
      var data = JSON.parse(xhr.responseText);
      document.getElementById('captcha_token').value=data.ctoken;
      real_login();
      return;
    }
    msg = new Dialog();
    msg.alert('Captcha server error:!' + xhr.status, {}).then((res) => { console.error(res); });
    return;
  }
  xhr.send(sendObject);
}
 
function TextPopup(payload, real_login, data) {
  dialog.open({
    dialogClass: 'custom',
    message: 'Text Captcha',
    accept: 'Check Captcha',
    template:'<img src="data:' + data.mimetype + ';base64,' + data.img + '"/>' +
      '<input type="text" name="ctext" value="">' +
      '<input type="hidden" name="ctype" value="' + data.ctype + '">' +
      '<input type="hidden" name="chash" value="' + data.chash + '">' +
      '<input type="hidden" name="payload" value="' + payload + '">'
  })
  dialog.waitForUser().then((res) => { captcha_check(res, real_login); })
}
function ClickPopup(payload, real_login, data) {
  dialog.open({
    dialogClass: 'custom',
    message: 'Click Captcha',
    accept: 'Check Captcha',
    template: '<canvas id="canvas" width="400" height="200"></canvas>' +
      '<h1>' + data.ctext + '</h1>' +
      '<input type="hidden" id="ctext" name="ctext" value="">' +
      '<input type="hidden" name="ctype" value="' + data.ctype + '">' +
      '<input type="hidden" name="chash" value="' + data.chash + '">' +
      '<input type="hidden" name="payload" value="' + payload + '">'
  })
  ClickCaptcha('canvas', {
    imgurl: 'data:image/png;base64,' + data.img,
    clickTimes: data.len,
    onOK: function(arr) {
      document.getElementById('ctext').value=JSON.stringify(arr);
    }
  });
  dialog.waitForUser().then((res) => { captcha_check(res, real_login); })
}

function getCaptcha(payload, real_login, url) {
  xhr=new XMLHttpRequest();
  xhr.open('GET', url, true);
  xhr.onreadystatechange = function() {
    if(xhr.readyState !== 4) { return; }
    if(xhr.status === 200) {
      var data = JSON.parse(xhr.responseText);
      if ( data.ctype == 'CLICK_CAPTCHA') {
        ClickPopup(payload, real_login, data);
        return;
      }
      if ( data.ctype == 'TEXT_CAPTCHA') {
        TextPopup(payload, real_login, data);
        return;
      }
      console.error(xhr.responseText)
    }
    msg = new Dialog();
    msg.alert('Captcha server error:!' + xhr.status, {}).then((res) => { console.error(res); });
  }
  xhr.send();
}
function captcha_login(real_login, payload) {
  if (payload == "") {
    msg = new Dialog();
    msg.alert('login payload NULL!', {}).then((res) => { console.error(res); });
    return;
  }
  getCaptcha(payload, real_login, CaptchaVerifyUrl);
}
