const express = require("express");
const { requireFirebaseAuth } = require("../middleware/firebaseAuth");
const { requireFirebaseAppCheck } = require("../middleware/appCheck");
const { acceptCashHubTerms, optOutCashHub, createCashHubRequest, commandCashHubRequest, createCashHubOffer, sendCashHubMessage, commandCashHubConversation } = require("../services/cashHubService");
const router = express.Router();
router.use(requireFirebaseAuth);
router.use(requireFirebaseAppCheck);

const buckets = new Map();
function rateLimit(scope, max, windowMs = 60000) {
  return (req, res, next) => {
    const now = Date.now();
    const key = `${scope}:${req.firebaseUid}`;
    if (buckets.size > 10000) {
      for (const [bucketKey, bucket] of buckets) {
        if (bucket.resetAt <= now) buckets.delete(bucketKey);
      }
    }
    const current = buckets.get(key);
    if (!current || current.resetAt <= now) {
      buckets.set(key, { count: 1, resetAt: now + windowMs });
      return next();
    }
    if (current.count >= max) return res.status(429).json({ error: "Too many CashRydr Hub requests. Please try again shortly." });
    current.count += 1;
    return next();
  };
}

router.post("/access/accept", rateLimit("access", 10), async (req,res,next)=>{try{res.json({ok:true,...await acceptCashHubTerms({uid:req.firebaseUid,role:req.body?.role})});}catch(e){next(e);}});
router.post("/access/opt-out", rateLimit("access", 10), async (req,res,next)=>{try{res.json({ok:true,...await optOutCashHub({uid:req.firebaseUid,role:req.body?.role})});}catch(e){next(e);}});
router.post("/requests", rateLimit("create", 10), async (req, res, next) => { try { res.status(201).json({ ok: true, ...(await createCashHubRequest({ uid: req.firebaseUid, payload: req.body })) }); } catch (e) { next(e); } });
router.post("/requests/:requestId/command", rateLimit("command", 60), async (req, res, next) => { try { res.json({ ok: true, ...(await commandCashHubRequest({ uid: req.firebaseUid, requestId: req.params.requestId, action: req.body?.action, payload: req.body })) }); } catch (e) { next(e); } });
router.post("/requests/:requestId/offers", rateLimit("offer", 20), async (req,res,next)=>{try{res.status(201).json({ok:true,...await createCashHubOffer({uid:req.firebaseUid,requestId:req.params.requestId,payload:req.body})});}catch(e){next(e);}});
router.post("/conversations/:conversationId/messages", rateLimit("message", 120), async (req,res,next)=>{try{res.status(201).json({ok:true,...await sendCashHubMessage({uid:req.firebaseUid,conversationId:req.params.conversationId,payload:req.body})});}catch(e){next(e);}});
router.post("/conversations/:conversationId/command", rateLimit("conversation-command", 30), async (req,res,next)=>{try{res.json({ok:true,...await commandCashHubConversation({uid:req.firebaseUid,conversationId:req.params.conversationId,action:req.body?.action,payload:req.body})});}catch(e){next(e);}});
module.exports = router;
