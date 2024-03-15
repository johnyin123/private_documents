;(function() {
  var opts = {
    imgurl: '',
    clickTimes: 2,
    clipWidth: 50,
    clipHeight: 50,
    fillStyle:'#000',
    lineWidth: 5,
    onOK: null,
    objs: []
  }
  function drawBorder(canvas, x, y, width, height) {
    var ctx = canvas.getContext("2d");
    ctx.fillStyle=opts.fillStyle;
    ctx.lineWidth = opts.lineWidth;
    // ctx.fillRect(x - (width/2), y - (height/2), width, height);
    ctx.strokeRect(x - (width/2), y - (height/2), width, height);
  }
  function getCursorPosition(canvas, event) {
    const rect = canvas.getBoundingClientRect();
    const x = event.clientX - rect.left;
    const y = event.clientY - rect.top;
    drawBorder(canvas, x, y, opts.clipWidth, opts.clipHeight);
    opts.objs.push({'x':x, 'y': y});
    if(opts.clickTimes<=opts.objs.length) {
      opts.onOK && opts.onOK(opts.objs);
      // reset(canvas);
    }
  }
  function reset(canvas) {
    var context = canvas.getContext("2d");
    var img = new Image();
    img.onload = function(){
      context.drawImage(img, 0, 0);
    };
    img.src = opts.imgurl;
    opts.objs=[];
  }
  var ClickCaptcha = function(canvas, options) {
    for(var k in options) {
      if(options.hasOwnProperty(k)) {
        opts[k] = options[k];
      }
    }
    if(!canvas || !opts.imgurl) {
      console.error("verify params is error");
      return;
    }
    if(typeof canvas === 'string') canvas = document.getElementById(canvas);
    if(canvas.tagName !== 'CANVAS') {
      console.error("param canvas must be canvas");
      return;
    }
    var context = canvas.getContext("2d");
    var img = new Image();
    img.onload = function(){
      context.drawImage(img, 0, 0);
    };
    img.src = opts.imgurl;
    canvas.addEventListener('mousedown', function(e) {
      if(opts.clickTimes<=opts.objs.length) { return; }
      getCursorPosition(canvas, e);
    })
  }
  if(typeof exports == "object") {
    module.exports = ClickCaptcha;
  } else if(typeof define == "function" && define.amd) {
    define([], function() {
      return ClickCaptcha;
    })
  } else if(window) {
    window.ClickCaptcha = ClickCaptcha;
  }
})()
