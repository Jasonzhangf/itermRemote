// Simple WebRTC Client for iTermRemote Loopback Test

const video = document.getElementById('video');
const status = document.getElementById('status');
const logBox = document.getElementById('log');
const connectBtn = document.getElementById('connectBtn');
const disconnectBtn = document.getElementById('disconnectBtn');

let ws = null;
let pc = null;

function log(msg) {
  const line = `${new Date().toISOString()} ${msg}`;
  logBox.textContent += line + '\n';
  logBox.scrollTop = logBox.scrollHeight;
  console.log(line);
}

function setStatus(s) {
  status.textContent = 'Status: ' + s;
}

connectBtn.onclick = async () => {
  if (ws) return;
  
  connectBtn.disabled = true;
  disconnectBtn.disabled = false;
  setStatus('connecting ws...');
  
  ws = new WebSocket('ws://127.0.0.1:8766');
  
  ws.onopen = async () => {
    log('WebSocket connected');
    setStatus('ws connected, creating peer...');
    await createPeer();
  };
  
  ws.onmessage = (e) => {
    const data = JSON.parse(e.data);
    log('WS <= ' + JSON.stringify(data));
    handleMessage(data);
  };
  
  ws.onclose = () => {
    log('WebSocket closed');
    setStatus('ws closed');
  };
  
  ws.onerror = (e) => {
    log('WebSocket error: ' + e);
    setStatus('ws error');
  };
};

disconnectBtn.onclick = () => {
  pc?.close();
  ws?.close();
  pc = null;
  ws = null;
  connectBtn.disabled = false;
  disconnectBtn.disabled = true;
  setStatus('idle');
};

async function createPeer() {
  pc = new RTCPeerConnection({
    iceServers: []
  });
  
  pc.ontrack = (e) => {
    log('Got remote track');
    if (e.streams.length > 0) {
      video.srcObject = e.streams[0];
      setStatus('streaming');
    }
  };
  
  pc.onicecandidate = (e) => {
    if (e.candidate) {
      send({
        type: 'ice',
        candidate: e.candidate.candidate,
        sdpMid: e.candidate.sdpMid,
        sdpMLineIndex: e.candidate.sdpMLineIndex
      });
    }
  };
  
  pc.onconnectionstatechange = () => {
    log('Connection state: ' + pc.connectionState);
  };
  
  const offer = await pc.createOffer({
    offerToReceiveAudio: true,
    offerToReceiveVideo: true
  });
  
  await pc.setLocalDescription(offer);
  
  send({
    type: 'offer',
    sdp: offer.sdp
  });
}

function handleMessage(data) {
  if (data.type === 'answer') {
    pc.setRemoteDescription(new RTCSessionDescription({
      type: 'answer',
      sdp: data.sdp
    })).then(() => {
      log('Set remote description (answer)');
    });
  } else if (data.type === 'ice') {
    pc.addIceCandidate(new RTCIceCandidate({
      candidate: data.candidate,
      sdpMid: data.sdpMid,
      sdpMLineIndex: data.sdpMLineIndex
    })).then(() => {
      log('Added ICE candidate');
    });
  }
}

function send(msg) {
  const payload = JSON.stringify(msg);
  log('WS => ' + payload);
  if (ws && ws.readyState === WebSocket.OPEN) {
    ws.send(payload);
  }
}

log('WebRTC Client loaded');
