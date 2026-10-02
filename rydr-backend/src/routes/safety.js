const express = require("express"); const { requireFirebaseAuth } = require("../middleware/firebaseAuth"); const { createSafetyReport, createSafetyAppeal } = require("../services/safetyService");
const router = express.Router(); router.use(requireFirebaseAuth);
router.post("/reports", async (req,res,next)=>{try{res.status(201).json({ok:true,...await createSafetyReport({uid:req.firebaseUid,payload:req.body})});}catch(e){next(e);}});
router.post("/appeals", async (req,res,next)=>{try{res.status(201).json({ok:true,...await createSafetyAppeal({uid:req.firebaseUid,payload:req.body})});}catch(e){next(e);}});
module.exports = router;
